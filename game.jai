Game_Memory :: struct {
    base_size: u32;
    base_pointer: *void;
    temporary_size: u32;
    temporary_pointer: *void;
}

Game_State :: struct {
    blue_offset: s32;
    green_offset: s32;
}

Game_Input :: struct {
    controllers: [5] Game_Controller_Input;
}

Game_Controller_Input :: struct {
    connected: bool;

    is_analog: bool;

    left_stick: Vector2;
    right_stick: Vector2;

    move_up: Game_Button_State;
    move_down: Game_Button_State;
    move_left: Game_Button_State;
    move_right: Game_Button_State;

    action_up: Game_Button_State;
    action_down: Game_Button_State;
    action_left: Game_Button_State;
    action_right: Game_Button_State;

    left_shoulder: Game_Button_State;
    right_shoulder: Game_Button_State;

    back: Game_Button_State;
    start: Game_Button_State;

  #place move_up;
    buttons: [12] Game_Button_State;
}

Game_Button_State :: enum_flags u32 {
    NONE :: 0x1;
    DOWN :: 0x1;
    START :: 0x2;
    END :: 0x4;
}

Offscreen_Buffer :: struct {
    // Pixels are always 32-bits wide, ordered in memory BB GG RR XX
    memory: *void;
    width: s32;
    height: s32;
    pitch: s32;
    bytes_per_pixel: s32;
}

render_weird_gradient :: (buffer: *Offscreen_Buffer, blue_offset: s32, green_offset: s32) {
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

draw_one_frame :: (memory: *Game_Memory, input: *Game_Input, buffer: *Offscreen_Buffer) {
    using game_state := cast(*Game_State) memory.base_pointer;

    render_weird_gradient(buffer, blue_offset, green_offset);

    for controller: input.controllers {
        if controller.connected {
            if controller.move_left & .DOWN {
                blue_offset -= 1;
            }
            if controller.move_right & .DOWN {
                blue_offset += 1;
            }
            if controller.move_down & .DOWN {
                green_offset -= 1;
            }
            if controller.move_up & .DOWN {
                green_offset += 1;
            }
        }
    }
}

