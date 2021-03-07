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

    pub fn init(fonts: FontSetDescriptor) ShaderError!Renderer {
        const draw_cells: DrawCells = block: {
            const vertex_source: [*:0]const u8 = @embedFile("shaders/draw_cells.vert");
            const fragment_source: [*:0]const u8 = @embedFile("shaders/draw_cells.frag");
            const program = try createShader(vertex_source, fragment_source);
            break :block .{
                .id = program,
                .cell_size_loc = glGetUniformLocation(program, "u_CellScale"),
                .stride_loc = glGetUniformLocation(program, "u_Stride"),
                .offset_loc = glGetUniformLocation(program, "u_Offset"),
            };
        };

        const blit_console: BlitConsole = block: {
            const vertex_source: [*:0]const u8 = @embedFile("shaders/blit.vert");
            const fragment_source: [*:0]const u8 = @embedFile("shaders/blit_console.frag");
            const program = try createShader(vertex_source, fragment_source);
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

        return Renderer{
            .font_set = font_set,
            .vao = vao,
            .draw_cells = draw_cells,
            .blit_console = blit_console,
        };
    }

    pub fn drawCells(renderer: Renderer, console: Console, offset: [2]f32, cells: CellGrid) void {
        glBindFramebuffer(GL_FRAMEBUFFER, console.fbo);
        glBindVertexArray(cells.vao);
        glUseProgram(renderer.draw_cells.id);

        glViewport(0, 0, @intCast(c_int, console.size[0]), @intCast(c_int, console.size[1]));

        glClearColor(1.0, 0.0, 1.0, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        glUniform2f(
            renderer.draw_cells.cell_size_loc,
            console.cellScale[0],
            console.cellScale[1],
        );
        glUniform2f(renderer.draw_cells.offset_loc, offset[0], offset[0]);
        glUniform1i(renderer.draw_cells.stride_loc, cells.stride);

        glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, 256);
    }

    pub fn blitConsole(renderer: Renderer, console: Console, offset: [2]u32) void {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glBindVertexArray(renderer.vao);
        glUseProgram(renderer.blit_console.id);

        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, console.texture);

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
    }

    const DrawCells = struct {
        id: c_uint,
        cell_size_loc: c_int,
        stride_loc: c_int,
        offset_loc: c_int,
    };

    const BlitConsole = struct {
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
    stride: i32,

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

        return result;
    }

    pub fn deinit(self: CellGrid) void {
        glDeleteVertexArrays(1, &self.vao);
        glDeleteBuffers(1, &self.vbo);
    }
};

pub const Console = struct {
    fbo: c_uint,
    texture: c_uint,
    size: [2]u32, // pixels
    cellScale: [2]f32,

    const Error = error{FramebufferIncomplete};

    pub fn init(size: [2]u32, cellSize: [2]u32) Error!Console {
        var result: Console = undefined;
        glGenTextures(1, &result.texture);

        glBindTexture(GL_TEXTURE_2D, result.texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        const width = size[0] * cellSize[0];
        const height = size[1] * cellSize[1];

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

        glGenFramebuffers(1, &result.fbo);
        glBindFramebuffer(GL_FRAMEBUFFER, result.fbo);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, result.texture, 0);
        const draw_buffers = [_]c_uint{GL_COLOR_ATTACHMENT0};
        glDrawBuffers(1, &draw_buffers);

        if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
            return Error.FramebufferIncomplete;

        glBindFramebuffer(GL_FRAMEBUFFER, 0);

        result.cellScale = .{
            2.0 * @intToFloat(f32, cellSize[0]) / @intToFloat(f32, width),
            -2.0 * @intToFloat(f32, cellSize[1]) / @intToFloat(f32, height),
        };

        result.size = .{ width, height };

        return result;
    }

    pub fn deinit(self: Console) void {
        glDeleteFramebuffers(1, &self.fbo);
        glDeleteTextures(1, &self.texture);
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
///
/// If the shaders fail to compile or link this function will panic with an error message describing the issue.
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
