#import "Basic";
#import "Windows";
#import "Windows_Utf8";
#import "Gamepad";
#import "Input";
#import "GL" (ENABLE_ALL_EXTENSIONS = true);

#load "game.jai";

#if OS == .WINDOWS {
    WR :: #import "Windows_Resources";
    #run WR.disable_runtime_console();
}

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

win32_init_opengl :: (window: HWND) {
    dc := GetDC(window);

    format: PIXELFORMATDESCRIPTOR;
    format.nSize = size_of(type_of(format));
    format.nVersion = 1;
    format.iPixelType = PFD_TYPE_RGBA;
    format.dwFlags = PFD_SUPPORT_OPENGL | PFD_DRAW_TO_WINDOW | PFD_DOUBLEBUFFER;
    format.cColorBits = 32;
    format.cAlphaBits = 8;
    format.iLayerType = PFD_MAIN_PLANE;

    suggested_format_index := ChoosePixelFormat(dc, *format);
    suggested_format: PIXELFORMATDESCRIPTOR;
    DescribePixelFormat(dc, suggested_format_index, size_of(type_of(suggested_format)), *suggested_format);
    SetPixelFormat(dc, suggested_format_index, *suggested_format);

    rc := wglCreateContext(dc);
    if wglMakeCurrent(dc, rc) {
        gl_load(*gl, wglGetProcAddress);

        // This is where we are currently putting OpenGL init stuff
        glGenTextures(1, *blit_texture_handle);

        if wglSwapIntervalEXT {
            wglSwapIntervalEXT(1);
        }
    }

    ReleaseDC(window, dc);
}

win32_display_buffer_in_window :: (buffer: *Win32_Offscreen_Buffer, dc: HDC, window_width: s32, window_height: s32) {
    // TODO: Aspect ratio correction
    // TODO: Play with stretch modes

    // StretchDIBits(dc, 0, 0, window_width, window_height, 0, 0, buffer.width, buffer.height, buffer.memory, *buffer.info, DIB_RGB_COLORS, .SRCCOPY);

    glViewport(0, 0, xx window_width, xx window_height);

    // glClearColor(.2, .3, .3, 1);
    // glClear(GL_COLOR_BUFFER_BIT);

    glBindTexture(GL_TEXTURE_2D, blit_texture_handle);

    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, xx buffer.width, xx buffer.height, 0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, buffer.memory);

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);
    glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);

    glEnable(GL_TEXTURE_2D);

    glMatrixMode(GL_TEXTURE);
    glLoadIdentity();

    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();

    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();

    glBegin(GL_TRIANGLES);

    p : float : 1.0;

    // Lower triangle
    glTexCoord2f(0, 0);
    glVertex2f(-p, -p);

    glTexCoord2f(1, 0);
    glVertex2f(p, -p);

    glTexCoord2f(1, 1);
    glVertex2f(p, p);

    // Upper triangle
    glTexCoord2f(0, 0);
    glVertex2f(-p, -p);

    glTexCoord2f(1, 1);
    glVertex2f(p, p);

    glTexCoord2f(0, 1);
    glVertex2f(-p, p);

    glEnd();

    SwapBuffers(dc);
}

main :: () {
    SetProcessDPIAware();
    timeBeginPeriod(1);

    init_gamepad();

    // initted := init_xinput();
    // assert(initted);

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
        log_error("Failed to register the window class.\n");
        return;
    }

    window := CreateWindowExW(WS_EX_APPWINDOW, wc.lpszClassName, utf8_to_wide("Handmade Hero",, temp), WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, null, null, hInstance, null);
    if !window {
        log_error("Failed to create the window.\n");
        return;
    }

    win32_init_opengl(window);

    print("%\n", to_string(glGetString(GL_VENDOR)));
    print("%\n", to_string(glGetString(GL_RENDERER)));
    print("%\n", to_string(glGetString(GL_VERSION)));

    win32_resize_dib_section(*backbuffer, 1920, 1080);

    ShowWindow(window, SW_SHOWDEFAULT);

    performance_frequency: s64;
    QueryPerformanceFrequency(*performance_frequency);

    last_counter: s64;
    QueryPerformanceCounter(*last_counter);

    while !should_quit_game {
        win32_process_pending_messages();

        // @Hack: This is needed because we are not using the Input module!
        memset(*input_button_states, 0, size_of(type_of(input_button_states)));
        update_gamepad();

        buffer: Offscreen_Buffer = ---;
        buffer.memory = backbuffer.memory;
        buffer.width = backbuffer.width;
        buffer.height = backbuffer.height;
        buffer.pitch = backbuffer.pitch;
        buffer.bytes_per_pixel = backbuffer.bytes_per_pixel;

        draw_one_frame(*buffer);

        window_width, window_height := win32_get_window_dimension(window);
        dc := GetDC(window);
        win32_display_buffer_in_window(*backbuffer, dc, window_width, window_height);
        ReleaseDC(window, dc);

        end_counter: s64;
        QueryPerformanceCounter(*end_counter);

        counter_elapsed := end_counter - last_counter;
        last_counter = end_counter;

        // print("ms = %\n", (1000*counter_elapsed) / cast(float) performance_frequency);
    }
}

#scope_file

should_quit_game := false;
backbuffer: Win32_Offscreen_Buffer;

blit_texture_handle: u32;
