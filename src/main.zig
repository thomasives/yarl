const std = @import("std");
const builtin = @import("builtin");
const panic = std.debug.panic;

const video = @import("video.zig");

usingnamespace @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
    @cInclude("STB/stb_image.h");
});

const WindowData = struct {
    width: c_int = 1024,
    height: c_int = 720,
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    _ = glfwSetErrorCallback(errorCallback);

    if (glfwInit() == 0) {
        panic("Failed to initialise GLFW\n", .{});
    }
    defer glfwTerminate();

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, 1);
    if (builtin.os.tag == .macos) {
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
    }

    var window_data = WindowData{};
    var window = glfwCreateWindow(
        window_data.width,
        window_data.height,
        "yarl",
        null,
        null,
    );

    if (window == null) {
        panic("Failed to create GLFW window\n", .{});
    }

    glfwSetWindowUserPointer(window, &window_data);

    glfwMakeContextCurrent(window);
    if (gladLoadGLLoader(@ptrCast(GLADloadproc, glfwGetProcAddress)) == 0) {
        panic("Failed to initialise GLAD\n", .{});
    }

    if (GLAD_GL_ARB_debug_output == 1) {
        glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS_ARB);
        glDebugMessageCallbackARB(glDebugOutput, null);
        glDebugMessageControlARB(GL_DONT_CARE, GL_DONT_CARE, GL_DONT_CARE, 0, null, GL_TRUE);
    }

    _ = glfwSetFramebufferSizeCallback(window, framebufferSizeCallback);
    _ = glfwSetKeyCallback(window, keyCallback);

    const renderer = block: {
        var width: c_int = undefined;
        var height: c_int = undefined;
        const font_png = @embedFile("../assets/terminal8x8.png");
        var font_image = stbi_load_from_memory(
            font_png,
            font_png.len,
            &width,
            &height,
            null,
            STBI_rgb,
        );
        defer stbi_image_free(font_image);

        std.debug.assert(width == 128);
        std.debug.assert(height == 128);

        const fontSetDescriptor = video.FontSetDescriptor{
            .native_cell_size = .{ 8.0, 8.0 },
            .fonts = &[_]video.FontDescriptor{
                .{
                    .width = width,
                    .height = height,
                    .data = font_image,
                },
            },
        };

        const renderer = try video.Renderer.init(fontSetDescriptor);
        break :block renderer;
    };
    defer renderer.deinit();

    glViewport(0, 0, window_data.width, window_data.height);

    const console = try video.Console.init(.{ 10, 10 }, .{ 16, 16 });
    defer console.deinit();

    const Cell = video.CellGrid.Cell;
    var map: [256]Cell = undefined;
    for (map) |*tile, index| {
        if (((index % 16) + (index / 16)) % 2 == 0) {
            tile.* = Cell{
                .bg = video.rgb(51, 77, 77),
                .fg = video.rgb(255, 128, 51),
                .code_point = @intCast(u8, index),
                .font_id = 0,
            };
        } else {
            tile.* = Cell{
                .bg = video.rgb(255, 128, 51),
                .fg = video.rgb(51, 77, 77),
                .code_point = @intCast(u8, index),
                .font_id = 0,
            };
        }
    }

    var data = video.CellGrid.init(&map, 16);
    defer data.deinit();

    while (glfwWindowShouldClose(window) == 0) {
        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glClearColor(0.2, 0.3, 0.3, 1.0);
        glClear(GL_COLOR_BUFFER_BIT);

        renderer.drawCells(console, .{ 5.0, 5.0 }, data);
        renderer.blitConsole(console, .{ 64, 64 });

        glfwSwapBuffers(window);
        glfwPollEvents();
    }
}

fn keyCallback(
    window: ?*GLFWwindow,
    key: c_int,
    scancode: c_int,
    action: c_int,
    mods: c_int,
) callconv(.C) void {
    if (key == GLFW_KEY_ESCAPE and action == GLFW_RELEASE) {
        glfwSetWindowShouldClose(window, 1);
    }
}

fn framebufferSizeCallback(
    window: ?*GLFWwindow,
    width: c_int,
    height: c_int,
) callconv(.C) void {
    var window_data = @intToPtr(*WindowData, @ptrToInt(glfwGetWindowUserPointer(window).?));
    window_data.width = width;
    window_data.height = height;
    glViewport(0, 0, width, height);
}

fn errorCallback(code: c_int, message: [*c]const u8) callconv(.C) void {
    const out = std.io.getStdErr().writer();
    _ = out.print("[ERROR::GLFW] ({}) {s}\n", .{ code, message }) catch unreachable;
}

fn glDebugOutput(
    source: c_uint,
    ty: c_uint,
    id: c_uint,
    severity: c_uint,
    length: c_int,
    message: [*c]const u8,
    user: ?*const c_void,
) callconv(.C) void {
    if (id == 131169 or id == 131185 or id == 131218 or id == 131204) return;

    const out = std.io.getStdErr().writer();
    _ = switch (ty) {
        GL_DEBUG_TYPE_ERROR_ARB => out.write("[ERROR::"),
        GL_DEBUG_TYPE_DEPRECATED_BEHAVIOR_ARB => out.write("[DEPRECATED::"),
        GL_DEBUG_TYPE_UNDEFINED_BEHAVIOR_ARB => out.write("[UNDEFINED::"),
        GL_DEBUG_TYPE_PORTABILITY_ARB => out.write("[PORTABILITY::"),
        GL_DEBUG_TYPE_PERFORMANCE_ARB => out.write("[PERFORMANCE::"),
        GL_DEBUG_TYPE_OTHER_ARB => out.write("[OTHER::"),
        else => out.write("[UNKNOWN::"),
    } catch unreachable;

    _ = switch (source) {
        GL_DEBUG_SOURCE_API_ARB => out.write("API::"),
        GL_DEBUG_SOURCE_WINDOW_SYSTEM_ARB => out.write("WINDOW::"),
        GL_DEBUG_SOURCE_SHADER_COMPILER_ARB => out.write("COMPILER::"),
        GL_DEBUG_SOURCE_THIRD_PARTY_ARB => out.write("THIRDPARTY::"),
        GL_DEBUG_SOURCE_APPLICATION_ARB => out.write("APPLICATION::"),
        GL_DEBUG_SOURCE_OTHER_ARB => out.write("OTHER::"),
        else => out.write("UNKNOWN::"),
    } catch unreachable;

    _ = switch (severity) {
        GL_DEBUG_SEVERITY_HIGH_ARB => out.write("HIGH] "),
        GL_DEBUG_SEVERITY_MEDIUM_ARB => out.write("MEDIUM] "),
        GL_DEBUG_SEVERITY_LOW_ARB => out.write("LOW] "),
        else => out.write("UNKNOWN] "),
    } catch unreachable;

    _ = out.print("({}) {s}\n", .{ id, message }) catch unreachable;
}
