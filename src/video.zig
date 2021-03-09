const std = @import("std");
const panic = std.debug.panic;

usingnamespace @cImport({
    @cInclude("glad/glad.h");
});

/// Width of a font image in cells
const FONT_WIDTH_CELLS = 16;
/// Height of a font image in cells
const FONT_HEIGHT_CELLS = 16;

/// Description of the font set to load onto the GPU
pub const FontSetDescriptor = struct {
    /// Size of single cell as it is stored on the GPU
    native_cell_size: [2]u32,
    /// Description of all the fonts to load into the font set
    fonts: []const FontDescriptor,
};

/// Description of a font to load into a font set
pub const FontDescriptor = struct {
    /// Width of the font data
    width: c_int,
    /// Height of the font data
    height: c_int,
    /// Font data in RGB u8 format
    data: [*c]u8,
};

pub const Renderer = struct {
    font_set: c_uint,
    vao: c_uint,
    draw_cells: DrawCells,
    blit_console: BlitConsole,
    replace_fg: ReplaceFg,
    replace_bg: ReplaceBg,

    pub fn init(fonts: FontSetDescriptor) ShaderError!Renderer {
        const draw_cells: DrawCells = block: {
            const vertex_source: [*:0]const u8 = @embedFile("shaders/draw_cells.vert");
            const fragment_source: [*:0]const u8 = @embedFile("shaders/draw_cells.frag");
            const program = try createShader(vertex_source, fragment_source);

            const index = glGetUniformBlockIndex(program, "Console");
            glUniformBlockBinding(program, index, 0);

            break :block .{
                .id = program,
                .stride_loc = glGetUniformLocation(program, "u_Stride"),
            };
        };

        const replace_fg: ReplaceFg = block: {
            const vertex_source: [*:0]const u8 = @embedFile("shaders/replace_fg.vert");
            const fragment_source: [*:0]const u8 = @embedFile("shaders/replace_fg.frag");
            const program = try createShader(vertex_source, fragment_source);

            const index = glGetUniformBlockIndex(program, "Console");
            glUniformBlockBinding(program, index, 0);

            break :block .{
                .id = program,
            };
        };

        const replace_bg: ReplaceBg = block: {
            const vertex_source: [*:0]const u8 = @embedFile("shaders/replace_bg.vert");
            const fragment_source: [*:0]const u8 = @embedFile("shaders/replace_bg.frag");
            const program = try createShader(vertex_source, fragment_source);

            const index = glGetUniformBlockIndex(program, "Console");
            glUniformBlockBinding(program, index, 0);

            break :block .{
                .id = program,
            };
        };

        const blit_console: BlitConsole = block: {
            const vertex_source: [*:0]const u8 = @embedFile("shaders/blit.vert");
            const fragment_source: [*:0]const u8 = @embedFile("shaders/blit_console.frag");
            const program = try createShader(vertex_source, fragment_source);

            const bg_color_loc = glGetUniformLocation(program, "u_BgColor");
            glUseProgram(program);
            glUniform1i(bg_color_loc, 1);
            glUseProgram(0);

            break :block .{
                .id = program,
            };
        };

        // OpenGL requires us to bind a Vertex Array Object even if
        // we don't actually need one for a simple blit.
        var vao: c_uint = undefined;
        glGenVertexArrays(1, &vao);
        glBindVertexArray(vao);
        defer glBindVertexArray(0);

        const font_set = try loadFontSet(fonts);

        glDepthFunc(GL_GEQUAL);

        return Renderer{
            .font_set = font_set,
            .vao = vao,
            .draw_cells = draw_cells,
            .blit_console = blit_console,
            .replace_fg = replace_fg,
            .replace_bg = replace_bg,
        };
    }

    pub fn clear(renderer: Renderer, color: Rgb) void {
        glClearColor(@intToFloat(f32, color.red) / 255.0, @intToFloat(f32, color.green) / 255.0, @intToFloat(f32, color.blue) / 255.0, 1.0);
        glClearDepth(0.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    }

    pub fn drawCells(renderer: Renderer, cells: CellGrid) void {
        glBindVertexArray(cells.vao);
        glUseProgram(renderer.draw_cells.id);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D_ARRAY, renderer.font_set);

        glUniform1i(renderer.draw_cells.stride_loc, cells.stride);

        glDisable(GL_DEPTH_TEST);

        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, cells.len);
    }

    pub fn replaceFg(renderer: Renderer, replacements: FgReplacements) void {
        glBindVertexArray(replacements.vao);
        glUseProgram(renderer.replace_fg.id);

        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D_ARRAY, renderer.font_set);

        glEnable(GL_DEPTH_TEST);

        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, replacements.len);
    }

    pub fn replaceBg(renderer: Renderer, replacements: BgReplacements) void {
        glBindVertexArray(replacements.vao);
        glUseProgram(renderer.replace_bg.id);

        glDisable(GL_DEPTH_TEST);

        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, replacements.len);
    }

    pub fn blitConsole(renderer: Renderer, console: Console, offset: [2]u32) void {
        glBindVertexArray(renderer.vao);
        glUseProgram(renderer.blit_console.id);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, console.fg_texture);

        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, console.bg_texture);

        glViewport(
            @intCast(c_int, offset[0]),
            @intCast(c_int, offset[1]),
            @intCast(c_int, console.size[0]),
            @intCast(c_int, console.size[1]),
        );

        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }

    pub fn deinit(self: Renderer) void {
        glDeleteTextures(1, &self.font_set);
        glDeleteProgram(self.draw_cells.id);
        glDeleteProgram(self.replace_fg.id);
        glDeleteProgram(self.replace_bg.id);
    }

    const DrawCells = struct {
        id: c_uint,
        stride_loc: c_int,
    };

    const BlitConsole = struct {
        id: c_uint,
    };

    const ReplaceFg = struct {
        id: c_uint,
    };

    const ReplaceBg = struct {
        id: c_uint,
    };
};

pub const Rgb = struct {
    red: u8,
    green: u8,
    blue: u8,
};

pub inline fn rgb(red: u8, green: u8, blue: u8) Rgb {
    return Rgb{ .red = red, .green = green, .blue = blue };
}

/// Console is a render target
pub const Console = struct {
    fbo: c_uint,
    ubo: c_uint,
    bg_texture: c_uint,
    fg_texture: c_uint,
    depth_buffer: c_uint,
    size: [2]u32, // pixels
    cellScale: [2]f32,

    const Error = error{FramebufferIncomplete};

    const Transform = struct {
        cell_size: [2]f32, // pixels
        offset: [2]f32, // cells
    };

    pub fn init(width: u32, height: u32) Error!Console {
        var result: Console = undefined;

        {
            glGenBuffers(1, &result.ubo);

            glBindBuffer(GL_UNIFORM_BUFFER, result.ubo);
            glBufferData(GL_UNIFORM_BUFFER, @sizeOf(Transform), null, GL_DYNAMIC_DRAW);
            glBindBuffer(GL_UNIFORM_BUFFER, 0);
        }

        {
            glGenTextures(1, &result.bg_texture);

            glBindTexture(GL_TEXTURE_2D, result.bg_texture);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

            glTexImage2D(
                GL_TEXTURE_2D,
                0,
                GL_RGB,
                @intCast(c_int, width),
                @intCast(c_int, height),
                0,
                GL_RGB,
                GL_UNSIGNED_BYTE,
                null,
            );
            glBindTexture(GL_TEXTURE_2D, 0);
        }

        {
            glGenTextures(1, &result.fg_texture);

            glBindTexture(GL_TEXTURE_2D, result.fg_texture);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

            glTexImage2D(
                GL_TEXTURE_2D,
                0,
                GL_RGBA,
                @intCast(c_int, width),
                @intCast(c_int, height),
                0,
                GL_RGB,
                GL_UNSIGNED_BYTE,
                null,
            );
            glBindTexture(GL_TEXTURE_2D, 0);
        }

        {
            glGenRenderbuffers(1, &result.depth_buffer);

            glBindRenderbuffer(GL_RENDERBUFFER, result.depth_buffer);
            glRenderbufferStorage(
                GL_RENDERBUFFER,
                GL_DEPTH_COMPONENT,
                @intCast(c_int, width),
                @intCast(c_int, height),
            );
            glBindRenderbuffer(GL_RENDERBUFFER, 0);
        }

        {
            glGenFramebuffers(1, &result.fbo);
            glBindFramebuffer(GL_FRAMEBUFFER, result.fbo);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.bg_texture, 0);
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT1, GL_TEXTURE_2D, result.fg_texture, 0);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, result.depth_buffer);
            const draw_buffers = [_]c_uint{ GL_COLOR_ATTACHMENT0, GL_COLOR_ATTACHMENT1 };
            glDrawBuffers(2, &draw_buffers);

            if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
                return Error.FramebufferIncomplete;

            glBindFramebuffer(GL_FRAMEBUFFER, 0);
        }

        result.size = .{ width, height };

        return result;
    }

    pub fn bind(self: Console) void {
        glBindFramebuffer(GL_FRAMEBUFFER, self.fbo);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, self.ubo);
        glViewport(0, 0, @intCast(c_int, self.size[0]), @intCast(c_int, self.size[1]));
    }

    pub fn unbind(self: Console) void {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glBindBufferBase(GL_UNIFORM_BUFFER, 0, 0);
    }

    pub fn sendTransform(self: Console, trans: Transform) void {
        glBindBuffer(GL_UNIFORM_BUFFER, self.ubo);
        var buffer: [4]f32 = undefined;
        buffer[0] = 2.0 * trans.cell_size[0] / @intToFloat(f32, self.size[0]);
        buffer[1] = 2.0 * trans.cell_size[1] / @intToFloat(f32, self.size[1]);
        buffer[2] = trans.offset[0];
        buffer[3] = trans.offset[1];
        glBufferSubData(GL_UNIFORM_BUFFER, 0, 4 * @sizeOf(f32), &buffer);
        glBindBuffer(GL_UNIFORM_BUFFER, 0);
    }

    pub fn deinit(self: Console) void {
        glDeleteFramebuffers(1, &self.fbo);
        glDeleteBuffers(1, &self.ubo);
        glDeleteTextures(1, &self.bg_texture);
        glDeleteTextures(1, &self.fg_texture);
    }
};

/// An array of cells stored on the GPU
pub const CellGrid = struct {
    pub const Cell = struct {
        bg: Rgb,
        fg: Rgb,
        code_point: u8,
        font_id: u8,
    };

    vao: c_uint,
    vbo: c_uint,
    stride: c_int,
    len: c_int,

    pub fn init(cells: []const Cell, stride: i32) CellGrid {
        var result: CellGrid = undefined;

        glGenVertexArrays(1, &result.vao);
        glBindVertexArray(result.vao);

        glGenBuffers(1, &result.vbo);

        glBindBuffer(GL_ARRAY_BUFFER, result.vbo);
        glBufferData(GL_ARRAY_BUFFER, @intCast(c_long, cells.len * @sizeOf(Cell)), cells.ptr, GL_STATIC_DRAW);

        var offset: ?*c_void = null;
        glVertexAttribPointer(0, 3, GL_UNSIGNED_BYTE, GL_TRUE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(0, 1);
        glEnableVertexAttribArray(0);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "fg"));
        glVertexAttribPointer(1, 3, GL_UNSIGNED_BYTE, GL_TRUE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(1, 1);
        glEnableVertexAttribArray(1);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "code_point"));
        glVertexAttribIPointer(2, 1, GL_UNSIGNED_BYTE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(2, 1);
        glEnableVertexAttribArray(2);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "font_id"));
        glVertexAttribIPointer(3, 1, GL_UNSIGNED_BYTE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(3, 1);
        glEnableVertexAttribArray(3);

        result.stride = stride;
        result.len = @intCast(c_int, cells.len);

        return result;
    }

    pub fn deinit(self: CellGrid) void {
        glDeleteVertexArrays(1, &self.vao);
        glDeleteBuffers(1, &self.vbo);
    }
};

/// Foreground replacement data stored on the GPU
pub const FgReplacements = struct {
    pub const Cell = struct {
        x: u16,
        y: u16,
        z: u8,
        color: Rgb,
        code_point: u8,
        font_id: u8,
    };

    vao: c_uint,
    vbo: c_uint,
    len: c_int,

    pub fn init(cells: []const Cell) FgReplacements {
        var result: FgReplacements = undefined;

        glGenVertexArrays(1, &result.vao);
        glBindVertexArray(result.vao);

        glGenBuffers(1, &result.vbo);

        glBindBuffer(GL_ARRAY_BUFFER, result.vbo);
        glBufferData(GL_ARRAY_BUFFER, @intCast(c_long, cells.len * @sizeOf(Cell)), cells.ptr, GL_STATIC_DRAW);

        var offset: ?*c_void = null;
        glVertexAttribPointer(0, 2, GL_UNSIGNED_SHORT, GL_FALSE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(0, 1);
        glEnableVertexAttribArray(0);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "z"));
        glVertexAttribPointer(1, 1, GL_UNSIGNED_BYTE, GL_TRUE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(1, 1);
        glEnableVertexAttribArray(1);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "color"));
        glVertexAttribPointer(2, 3, GL_UNSIGNED_BYTE, GL_TRUE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(2, 1);
        glEnableVertexAttribArray(2);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "code_point"));
        glVertexAttribIPointer(3, 1, GL_UNSIGNED_BYTE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(3, 1);
        glEnableVertexAttribArray(3);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "font_id"));
        glVertexAttribIPointer(4, 1, GL_UNSIGNED_BYTE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(4, 1);
        glEnableVertexAttribArray(4);

        result.len = @intCast(c_int, cells.len);

        return result;
    }

    pub fn deinit(self: FgReplacements) void {
        glDeleteVertexArrays(1, &self.vao);
        glDeleteBuffers(1, &self.vbo);
    }
};

/// Background replacement data stored on the GPU
pub const BgReplacements = struct {
    pub const Cell = struct {
        x: u16,
        y: u16,
        color: Rgb,
    };

    vao: c_uint,
    vbo: c_uint,
    len: c_int,

    pub fn init(cells: []const Cell) BgReplacements {
        var result: BgReplacements = undefined;

        glGenVertexArrays(1, &result.vao);
        glBindVertexArray(result.vao);

        glGenBuffers(1, &result.vbo);

        glBindBuffer(GL_ARRAY_BUFFER, result.vbo);
        glBufferData(GL_ARRAY_BUFFER, @intCast(c_long, cells.len * @sizeOf(Cell)), cells.ptr, GL_STATIC_DRAW);

        var offset: ?*c_void = null;
        glVertexAttribPointer(0, 2, GL_UNSIGNED_SHORT, GL_FALSE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(0, 1);
        glEnableVertexAttribArray(0);

        offset = @intToPtr(*c_void, @byteOffsetOf(Cell, "color"));
        glVertexAttribPointer(1, 3, GL_UNSIGNED_BYTE, GL_TRUE, @sizeOf(Cell), offset);
        glVertexAttribDivisor(1, 1);
        glEnableVertexAttribArray(1);

        result.len = @intCast(c_int, cells.len);

        return result;
    }

    pub fn deinit(self: BgReplacements) void {
        glDeleteVertexArrays(1, &self.vao);
        glDeleteBuffers(1, &self.vbo);
    }
};

pub const ShaderError = error{
    VertexCompliation,
    FragmentCompliation,
    Linkage,
};

/// Compile an link a shader program from the vertex and fragment sources.
///
/// Returns an OpenGL program id.  It is the callers responsiblity to free the program with glDeleteProgram.
fn createShader(vertex_source: [*:0]const u8, fragment_source: [*:0]const u8) ShaderError!c_uint {
    var vertex_shader: c_uint = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertex_shader, 1, &vertex_source, null);
    glCompileShader(vertex_shader);

    var success: c_int = undefined;
    glGetShaderiv(vertex_shader, GL_COMPILE_STATUS, &success);
    if (success == 0) {
        return ShaderError.VertexCompliation;
    }

    var fragment_shader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragment_shader, 1, &fragment_source, null);
    glCompileShader(fragment_shader);

    glGetShaderiv(fragment_shader, GL_COMPILE_STATUS, &success);
    if (success == 0) {
        return ShaderError.FragmentCompliation;
    }

    var program = glCreateProgram();
    glAttachShader(program, vertex_shader);
    glAttachShader(program, fragment_shader);
    glLinkProgram(program);

    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (success == 0) {
        return ShaderError.Linkage;
    }
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);

    return program;
}

/// Load the font set to the GPU and set it as the GL_TEXTURE_2D_ARRAY in first texture unit
fn loadFontSet(desc: FontSetDescriptor) ShaderError!c_uint {
    var result: c_uint = undefined;
    glGenTextures(1, &result);

    glBindTexture(GL_TEXTURE_2D_ARRAY, result);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D_ARRAY, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    const width = @intCast(c_int, FONT_WIDTH_CELLS * desc.native_cell_size[0]);
    const height = @intCast(c_int, FONT_HEIGHT_CELLS * desc.native_cell_size[1]);
    const layers = @intCast(c_int, desc.fonts.len);

    glTexImage3D(GL_TEXTURE_2D_ARRAY, 0, GL_RED, width, height, layers, 0, GL_RGB, GL_UNSIGNED_BYTE, null);
    glBindTexture(GL_TEXTURE_2D_ARRAY, 0);

    const blit_font = block: {
        const vertex_source: [*:0]const u8 = @embedFile("shaders/blit.vert");
        const fragment_source: [*:0]const u8 = @embedFile("shaders/blit_font.frag");
        const program = try createShader(vertex_source, fragment_source);
        break :block .{
            .id = program,
        };
    };
    glUseProgram(blit_font.id);
    defer glUseProgram(0);
    defer glDeleteProgram(blit_font.id);

    var fbo: c_uint = undefined;
    glGenFramebuffers(1, &fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, fbo);
    defer glBindFramebuffer(GL_FRAMEBUFFER, 0);
    defer glDeleteFramebuffers(1, &fbo);

    const attachments = [_]c_uint{GL_COLOR_ATTACHMENT0};
    glDrawBuffers(1, &attachments);
    glViewport(0, 0, width, height);

    var font: c_uint = undefined;
    glGenTextures(1, &font);

    glBindTexture(GL_TEXTURE_2D, font);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    defer glBindTexture(GL_TEXTURE_2D, 0);
    defer glDeleteTextures(1, &font);

    for (desc.fonts) |font_desc, layer| {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, width, height, 0, GL_RGB, GL_UNSIGNED_BYTE, font_desc.data);
        glFramebufferTextureLayer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, result, 0, @intCast(c_int, layer));
        glClearColor(0.0, 0.0, 0.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }

    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D_ARRAY, result);

    return result;
}
