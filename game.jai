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

draw_one_frame :: (buffer: *Offscreen_Buffer) {
    render_weird_gradient(buffer, blue_offset, green_offset);

    if gamepad.connected {
        if gamepad.buttons[Gamepad_Code.A] & Key_Current_State.DOWN {
            green_offset += 1;
        }
    }

    blue_offset += 1;
}


#scope_file

blue_offset: s32;
green_offset: s32;

