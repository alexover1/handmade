#import "Basic";
#import "Windows";
#import "Windows_Utf8";

win32_get_window_dimension :: (window: HWND) -> width: s32, height: s32 {
    client_rect: RECT;
    GetClientRect(window, *client_rect);

    width := client_rect.right - client_rect.left;
    height := client_rect.bottom - client_rect.top;

    return width, height;
}

Win32_Offscreen_Buffer :: struct {
    info: BITMAPINFO;
    memory: *void;
    width: s32;
    height: s32;
    pitch: s32;
    bytes_per_pixel: s32;
}

win32_resize_dib_section :: (buffer: *Win32_Offscreen_Buffer, width: s32, height: s32) {
    // TODO: Bulletproof this.
    // Maybe don't free first, free after, then free first if that fails.

    if buffer.memory {
        free(buffer.memory);
    }

    buffer.width = width;
    buffer.height = height;
    buffer.bytes_per_pixel = 4;

    // NOTE: When the biHeight field is negative, this is the clue to
    // Windows to treat this bitmap as top-down, not bottom-up, meaning that
    // the first three bytes of the image are the color for the top left pixel
    // in the bitmap, not the bottom left!
    buffer.info.bmiHeader.biSize = size_of(type_of(buffer.info.bmiHeader));
    buffer.info.bmiHeader.biWidth = buffer.width;
    buffer.info.bmiHeader.biHeight = -buffer.height;
    buffer.info.bmiHeader.biPlanes = 1;
    buffer.info.bmiHeader.biBitCount = 32;
    buffer.info.bmiHeader.biCompression = BI_RGB;

    bitmap_memory_size := (buffer.width * buffer.height) * buffer.bytes_per_pixel;
    buffer.memory = alloc(bitmap_memory_size);

    buffer.pitch = width * buffer.bytes_per_pixel;

    // TODO: Probably clear this to black
}

win32_main_window_callback :: (window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> s64 #c_call {
    push_context {
        if message == {
        case WM_CLOSE;
            // TODO: Handle this with a message to the user
            should_quit_game = true;

        case WM_DESTROY;
            // TODO: Handle this as an error - recreate window?
            should_quit_game = true;

        case WM_SYSKEYDOWN; #through;
        case WM_SYSKEYUP;   #through;
        case WM_KEYDOWN;    #through;
        case WM_KEYUP;
            assert(false, "Keyboard input came in through a non-dispatch message!");

        case WM_PAINT;
            paint: PAINTSTRUCT;
            dc := BeginPaint(window, *paint);

            window_width, window_height := win32_get_window_dimension(window);
            win32_display_buffer_in_window(*backbuffer, dc, window_width, window_height);

            EndPaint(window, *paint);
        case;

            return DefWindowProcW(window, message, wparam, lparam);
        }

        return 0;
    }
}

win32_process_pending_messages :: () {
    message: MSG;
    while true {
        got_message: s32;

        skip_messages := u32.[
            // NOTE(casey): We were previously skipping WM_PAINT, but it appears
            // that it is generally dispatched directly to the window in almost
            // all cases, so there is no sense generating an additional spurious
            // call to PeekMessage to skip a message that (almost?) never goes
            // through the main thread message loop.
            //                WM_PAINT,

            // NOTE(casey): We observed bad behavior when skipping WM_MOUSEMOVE (at
            // least on Windows 10), so it _cannot_ be skipped or queued mouse movements
            // at rapid speed seem to create a scenario where PeekMessage will take in
            // the tens of millions of cycles just to return that it _doesn't_ have
            // a message!  (Or more specifically, 4 calls to PeekMessage were taking
            // tens of millions of cycles, on the order of 5 million cycles per call).
            //                WM_MOUSEMOVE,

            // TODO(casey): Why are we getting 0x738 (1848) sent to us?  This is a WM_USER
            // message!
            0x738,
            0xFFFFFFFF,
        ];

        last_message: u32;
        for skip_messages {
            got_message = PeekMessageW(*message, null, last_message, it - 1, PM_REMOVE);
            if got_message  break;

            last_message = it + 1;
        }

        if !got_message  break;

        if message.message == {
        case WM_QUIT;
            should_quit_game = true;

        case WM_SYSKEYDOWN; #through;
        case WM_SYSKEYUP;   #through;
        case WM_KEYDOWN;    #through;
        case WM_KEYUP;
            vk_code := cast(u32) message.wParam;

            alt_key_was_down := (message.lParam & (1 << 29));
            shift_key_was_down := (GetKeyState(VK_SHIFT) & (1 << 15));

            was_down := ((message.lParam & (1 << 30)) != 0);
            is_down := ((message.lParam & (1 << 31)) == 0);

            if was_down {
                if vk_code == VK_F4 && alt_key_was_down {
                    should_quit_game = true;
                } else if vk_code == VK_RETURN && alt_key_was_down {
                    if message.hwnd {
                        // ToggleFullscreen(message.hwnd);
                    }
                }
            }

        case;
            TranslateMessage(*message);
            DispatchMessageW(*message);
        }
    }
}

win32_display_buffer_in_window :: (buffer: *Win32_Offscreen_Buffer, dc: HDC, window_width: s32, window_height: s32) {
    // TODO: Aspect ratio correction
    // TODO: Play with stretch modes

    StretchDIBits(dc, 0, 0, window_width, window_height, 0, 0, buffer.width, buffer.height, buffer.memory, *buffer.info, DIB_RGB_COLORS, .SRCCOPY);
}

win32_init_direct_sound :: () {
    // dsound := LoadLibraryW(utf8_to_wide("dsound.dll",, temp));
    // if dsound {
    //     PROC_DirectSoundCreate :: #type () -> ;
    //     DirectSoundCreate :=
    // }
}

render_weird_gradient :: (buffer: *Win32_Offscreen_Buffer, blue_offset: s32, green_offset: s32) {
    row := cast(*u8) buffer.memory;
    for y: 0..buffer.height-1 {
        pixel := cast(*u32) row;
        for x: 0..buffer.width-1 {
            blue := cast,trunc(u8) (x + blue_offset);
            green := cast,trunc(u8) (y + green_offset);
            pixel.* = (cast(u32, green) << 8) | blue;
            pixel += 1;
        }
        row += buffer.pitch;
    }
}

main :: () {
    SetProcessDPIAware();
    timeBeginPeriod(1);

    hInstance := GetModuleHandleW(null);

    wc: WNDCLASSEXW;
    wc.cbSize = size_of(type_of(wc));
    wc.style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
    wc.lpfnWndProc = xx win32_main_window_callback;
    wc.hInstance = hInstance;
    wc.hCursor = LoadCursorW(null, IDC_ARROW);
    wc.hbrBackground = GetStockObject(BLACK_BRUSH);
    // wc.hIcon;
    wc.lpszClassName = utf8_to_wide("HandmadeHeroWindowClass",, temp);

    if RegisterClassExW(*wc) == 0 {
        log_error("RegisterClassExW returned 0.\n");
        return;
    }

    window := CreateWindowExW(WS_EX_APPWINDOW, wc.lpszClassName, utf8_to_wide("Handmade Hero",, temp), WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, null, null, hInstance, null);
    if !window {
        log_error("CreateWindowExW failed!\n");
        return;
    }

    win32_init_direct_sound();

    dc := GetDC(window);
    win32_resize_dib_section(*backbuffer, 1280, 720);

    ShowWindow(window, SW_SHOWDEFAULT);

    blue_offset: s32;
    green_offset: s32;
    while !should_quit_game {
        win32_process_pending_messages();

        render_weird_gradient(*backbuffer, blue_offset, green_offset);

        window_width, window_height := win32_get_window_dimension(window);
        win32_display_buffer_in_window(*backbuffer, dc, window_width, window_height);

        blue_offset += 1;
    }
}

#scope_file

should_quit_game := false;
backbuffer: Win32_Offscreen_Buffer;

#run {
    WR :: #import "Windows_Resources";
    WR.disable_runtime_console();
}

// @@: This came from the fact that StretchDIBits wasn't in Windows.jai...
user :: #system_library "User32";
gdi :: #system_library "Gdi32";

SendMessageW :: (window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> s64 #foreign user;

PAINTSTRUCT :: struct {
    hdc: HDC;
    fErase: BOOL;
    rcPaint: RECT;
    fRestore: BOOL;
    fIncUpdate: BOOL;
    rgbReserved: [32]u8;
}

BeginPaint :: (hWnd: HWND, lpPaint: *PAINTSTRUCT) -> HDC #foreign user;
EndPaint :: (hWnd: HWND, lpPaint: *PAINTSTRUCT) #foreign user;

// @@: This should be in Windows.jai!
StretchDIBits :: (hdc: HDC, xDest: s32, yDest: s32, DestWidth: s32, DestHeight: s32, xSrc: s32, ySrc: s32, SrcWidth: s32, SrcHeight: s32, lpBits: *void, lpBmi: *BITMAPINFO, iUsage: u32, rop: ROP) #foreign gdi;
