#import "Math";
#import "Basic";
#import "Windows";
#import "Windows_Utf8";
#import "GL" (ENABLE_ALL_EXTENSIONS = true);

RELEASE :: false;

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

win32_toggle_fullscreen :: (window: HWND) {
    style := GetWindowLongW(window, GWL_STYLE);

    if style & WS_OVERLAPPEDWINDOW {
        monitor_info: MONITORINFO;
        monitor_info.cbSize = size_of(type_of(monitor_info));
        if GetWindowPlacement(window, *saved_window_position) {
            if GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY), *monitor_info) {
                SetWindowPos(window, HWND_TOP,
                             monitor_info.rcMonitor.left, monitor_info.rcMonitor.top,
                             monitor_info.rcMonitor.right - monitor_info.rcMonitor.left,
                             monitor_info.rcMonitor.bottom - monitor_info.rcMonitor.top,
                             SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
            }
        }
    } else {
        SetWindowPlacement(window, *saved_window_position);
        SetWindowPos(window, null, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER |
                     SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
    }
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
            win32_display_buffer_in_window(*global_backbuffer, dc, window_width, window_height);

            EndPaint(window, *paint);
        case;

            return DefWindowProcW(window, message, wparam, lparam);
        }

        return 0;
    }
}

win32_init_xinput :: () -> bool {
    xinput_library := LoadLibraryW(utf8_to_wide("xinput1_4.dll",, temp));
    if !xinput_library {
        xinput_library = LoadLibraryW(utf8_to_wide("xinput1_3.dll",, temp));
    }

    if !xinput_library return false;

    xinput_get_state := GetProcAddress(xinput_library, "XInputGetState");
    if xinput_get_state  XInputGetState = xinput_get_state;

    xinput_set_state := GetProcAddress(xinput_library, "XInputSetState");
    if xinput_set_state  XInputSetState = xinput_set_state;

    return true;
}

XINPUT_GAMEPAD :: struct {
    wButtons: u16;
    bLeftTrigger: u8;
    bRightTrigger: u8;
    sThumbLX: s16;
    sThumbLY: s16;
    sThumbRX: s16;
    sThumbRY: s16;
}

XINPUT_STATE :: struct {
    dwPacketNumber: u32;
    Gamepad: XINPUT_GAMEPAD;
}

XINPUT_VIBRATION :: struct {
    wLeftMotorSpeed: u16;
    wRightMotorSpeed: u16;
}

//
// Constants for gamepad buttons
//
XINPUT_GAMEPAD_DPAD_UP ::          0x0001;
XINPUT_GAMEPAD_DPAD_DOWN ::        0x0002;
XINPUT_GAMEPAD_DPAD_LEFT ::        0x0004;
XINPUT_GAMEPAD_DPAD_RIGHT ::       0x0008;
XINPUT_GAMEPAD_START ::            0x0010;
XINPUT_GAMEPAD_BACK ::             0x0020;
XINPUT_GAMEPAD_LEFT_THUMB ::       0x0040;
XINPUT_GAMEPAD_RIGHT_THUMB ::      0x0080;
XINPUT_GAMEPAD_LEFT_SHOULDER ::    0x0100;
XINPUT_GAMEPAD_RIGHT_SHOULDER ::   0x0200;
XINPUT_GAMEPAD_A ::                0x1000;
XINPUT_GAMEPAD_B ::                0x2000;
XINPUT_GAMEPAD_X ::                0x4000;
XINPUT_GAMEPAD_Y ::                0x8000;

//
// Gamepad thresholds
//
XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE ::  7849;
XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE :: 8689;
XINPUT_GAMEPAD_TRIGGER_THRESHOLD ::    30;

// User index definitions
XUSER_MAX_COUNT ::                 4;

XUSER_INDEX_ANY ::                 0x000000FF;

ERROR_DEVICE_NOT_CONNECTED :: 1167; // From winerror.h

XInputGetState := (dwUserIndeX: u32, pState: *XINPUT_STATE) -> u32 #c_call {
    return ERROR_DEVICE_NOT_CONNECTED;
}
XInputSetState := (dwUserIndeX: u32, pVibration: *XINPUT_VIBRATION) -> u32 #c_call {
    return ERROR_DEVICE_NOT_CONNECTED;
}

win32_process_keyboard_message :: () {
}

win32_process_xinput_digital_button :: (xinput_button_state: u32, button_bit: u32, state: *Game_Button_State) {
    pressed := (xinput_button_state & button_bit) == button_bit;
    was_pressed := (state.* & .DOWN) && !(state.* & .END);

    if pressed == was_pressed return;

    if pressed {
        state.* |= Game_Button_State.DOWN | .START;
    } else {
        state.* |= .END;
    }
}

win32_process_xinput_stick_value :: (value: s16, dead_zone_threshhold: s16) -> float {
    result: float;

    if value < -dead_zone_threshhold {
        result = cast(float, value + dead_zone_threshhold) / (32768.0 - dead_zone_threshhold);
    } else if value > dead_zone_threshhold {
        result = cast(float, value - dead_zone_threshhold) / (32767.0 - dead_zone_threshhold);
    }

    return result;
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
                        win32_toggle_fullscreen(message.hwnd);
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

    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

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

    win32_init_xinput();

    xbox_controller_present: [XUSER_MAX_COUNT] bool;
    for *present: xbox_controller_present {
        present.* = true;
    }

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

    window := CreateWindowExW(0, wc.lpszClassName, utf8_to_wide("Handmade Hero",, temp), WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, null, null, hInstance, null);
    if !window {
        log_error("Failed to create the window.\n");
        return;
    }

    win32_init_opengl(window);

    print("%\n", to_string(glGetString(GL_VENDOR)));
    print("%\n", to_string(glGetString(GL_RENDERER)));
    print("%\n", to_string(glGetString(GL_VERSION)));

    win32_resize_dib_section(*global_backbuffer, 1920, 1080);

    base_address := ifx !RELEASE then 2*1024*1024*1024;

    game_memory: Game_Memory;
    game_memory.base_size = 256*1024*1024;
    game_memory.base_pointer = VirtualAlloc(xx base_address, game_memory.base_size,
                                            MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);

    game_input: Game_Input;

    ShowWindow(window, SW_SHOWDEFAULT);

    while !should_quit_game {
        win32_process_pending_messages();

        // TODO: Need to not poll disconnected controllers to avoid
        // xinput frame rate hit on older libraries...
        // TODO: Should we poll this more frequently?
        max_controller_count := XUSER_MAX_COUNT;
        if max_controller_count > game_input.controllers.count {
            max_controller_count = game_input.controllers.count;
        }

        for 0..max_controller_count - 1 {
            controller := *game_input.controllers[it];

            controller_state: XINPUT_STATE;
            if xbox_controller_present[it] && XInputGetState(xx it, *controller_state) == 0 /*ERROR_SUCCESS*/ {
                controller.connected = true;

                // @Speed: Instead of doing this, we could mantain old_state and new_state.
                mask     := ~Game_Button_State.START;
                end_mask := ~(Game_Button_State.END | .DOWN | .START);
                for * controller.buttons {
                    if it.* & .END {
                        it.* &= end_mask;
                    } else {
                        it.* &= mask;
                    }
                }

                pad := *controller_state.Gamepad;

                controller.left_stick.x = win32_process_xinput_stick_value(pad.sThumbLX, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
                controller.left_stick.y = win32_process_xinput_stick_value(pad.sThumbLY, XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE);
                controller.right_stick.x = win32_process_xinput_stick_value(pad.sThumbRX, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);
                controller.right_stick.y = win32_process_xinput_stick_value(pad.sThumbRY, XINPUT_GAMEPAD_RIGHT_THUMB_DEADZONE);

                if controller.left_stick.x != 0 || controller.left_stick.y != 0 {
                    controller.is_analog = true;
                }

                if pad.wButtons & XINPUT_GAMEPAD_DPAD_UP {
                    controller.left_stick.y = 1;
                    controller.is_analog = false;
                }

                if pad.wButtons & XINPUT_GAMEPAD_DPAD_DOWN {
                    controller.left_stick.y = -1;
                    controller.is_analog = false;
                }

                if pad.wButtons & XINPUT_GAMEPAD_DPAD_LEFT {
                    controller.left_stick.x = -1;
                    controller.is_analog = false;
                }

                if pad.wButtons & XINPUT_GAMEPAD_DPAD_RIGHT {
                    controller.left_stick.x = 1;
                    controller.is_analog = false;
                }

                threshold : float : 0.5;
                win32_process_xinput_digital_button(ifx controller.left_stick.x < -threshold then cast(u32)1, 1, *controller.move_left);
                win32_process_xinput_digital_button(ifx controller.left_stick.x > threshold then cast(u32)1, 1, *controller.move_right);
                win32_process_xinput_digital_button(ifx controller.left_stick.y < -threshold then cast(u32)1, 1, *controller.move_down);
                win32_process_xinput_digital_button(ifx controller.left_stick.y > threshold then cast(u32)1, 1, *controller.move_up);

                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_A, *controller.action_down);
                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_B, *controller.action_right);
                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_X, *controller.action_left);
                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_Y, *controller.action_up);

                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_LEFT_SHOULDER, *controller.left_shoulder);
                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_RIGHT_SHOULDER, *controller.right_shoulder);
                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_START, *controller.start);
                win32_process_xinput_digital_button(pad.wButtons, XINPUT_GAMEPAD_BACK, *controller.back);
            } else {
                // The controller is not available
                controller.connected = false;
                xbox_controller_present[it] = false;
            }
        }

/*
        for controller: game_input.controllers {
            if controller.connected {
                for controller.buttons {
                    if it & .DOWN {
                        print("%\n", it_index);
                    }
                }
            }
        }
*/

        buffer: Offscreen_Buffer = ---;
        buffer.memory = global_backbuffer.memory;
        buffer.width = global_backbuffer.width;
        buffer.height = global_backbuffer.height;
        buffer.pitch = global_backbuffer.pitch;
        buffer.bytes_per_pixel = global_backbuffer.bytes_per_pixel;

        draw_one_frame(*game_memory, *game_input, *buffer);

        window_width, window_height := win32_get_window_dimension(window);
        dc := GetDC(window);
        win32_display_buffer_in_window(*global_backbuffer, dc, window_width, window_height);
        ReleaseDC(window, dc);
    }
}

#scope_file

should_quit_game := false;
global_backbuffer: Win32_Offscreen_Buffer;
saved_window_position: WINDOWPLACEMENT = .{ length = size_of(WINDOWPLACEMENT) };

blit_texture_handle: u32;
