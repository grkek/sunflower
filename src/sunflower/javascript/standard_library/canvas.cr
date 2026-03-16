# src/sunflower/javascript/standard_library/canvas.cr
#
# 2D game engine module using OpenGL via GTK4's GLArea.
# All rendering is batched and GPU-accelerated.
#
# JS API:
#   import { Canvas } from "canvas";
#   const canvas = new Canvas("pong", { width: 800, height: 500, framesPerSecond: 60 });
#   canvas.onDraw((ctx) => { ctx.clear("#000"); ctx.fillRect(10, 10, 50, 50, "#f00"); });
#   canvas.onUpdate((dt) => { if (canvas.isKeyDown("w")) { ... } });
#   canvas.start();

module Sunflower
  module JavaScript
    module StandardLibrary
      class Canvas < Module
        Log = ::Log.for(self)

        @@active_canvas_id : String? = nil
        @@active_interval : UInt32 = 16_u32

        class State
          property width : Int32 = 800
          property height : Int32 = 600
          property frames_per_second : Int32 = 60
          property running : Bool = false
          property draw_commands : Array(DrawCommand) = [] of DrawCommand
          property keys_held : Set(String) = Set(String).new
          property mouse_x : Float64 = 0.0
          property mouse_y : Float64 = 0.0
          property mouse_down : Bool = false
          property renderer : Graphics::Renderer = Graphics::Renderer.new
          property text_renderer : Graphics::TextRenderer = Graphics::TextRenderer.new

          @@canvases = {} of String => State

          def self.get(id : String) : State
            @@canvases[id] ||= State.new
          end

          def self.remove(id : String)
            if state = @@canvases.delete(id)
              state.renderer.cleanup
            end
          end
        end

        abstract struct DrawCommand
        end

        struct ClearCommand < DrawCommand
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64

          def initialize(@r, @g, @b, @a); end
        end

        struct FillRectCommand < DrawCommand
          getter x : Float64
          getter y : Float64
          getter w : Float64
          getter h : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64

          def initialize(@x, @y, @w, @h, @r, @g, @b, @a); end
        end

        struct StrokeRectCommand < DrawCommand
          getter x : Float64
          getter y : Float64
          getter w : Float64
          getter h : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64
          getter line_width : Float64

          def initialize(@x, @y, @w, @h, @r, @g, @b, @a, @line_width); end
        end

        struct FillCircleCommand < DrawCommand
          getter x : Float64
          getter y : Float64
          getter radius : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64

          def initialize(@x, @y, @radius, @r, @g, @b, @a); end
        end

        struct StrokeCircleCommand < DrawCommand
          getter x : Float64
          getter y : Float64
          getter radius : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64
          getter line_width : Float64

          def initialize(@x, @y, @radius, @r, @g, @b, @a, @line_width); end
        end

        struct DrawLineCommand < DrawCommand
          getter x1 : Float64
          getter y1 : Float64
          getter x2 : Float64
          getter y2 : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64
          getter line_width : Float64

          def initialize(@x1, @y1, @x2, @y2, @r, @g, @b, @a, @line_width); end
        end

        struct FillTextCommand < DrawCommand
          getter text : String
          getter x : Float64
          getter y : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64
          getter size : Float64

          def initialize(@text, @x, @y, @r, @g, @b, @a, @size); end
        end

        struct FillTriangleCommand < DrawCommand
          getter x1 : Float64
          getter y1 : Float64
          getter x2 : Float64
          getter y2 : Float64
          getter x3 : Float64
          getter y3 : Float64
          getter r : Float64
          getter g : Float64
          getter b : Float64
          getter a : Float64

          def initialize(@x1, @y1, @x2, @y2, @x3, @y3, @r, @g, @b, @a); end
        end

        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          register_draw_bindings(sandbox, engine)
          register_control_bindings(sandbox, engine)
          install_js_module(sandbox)
        end

        def self.parse_hex(hex : String) : {Float64, Float64, Float64, Float64}
          hex = hex.lstrip('#')
          return {0.0, 0.0, 0.0, 1.0} if hex.size < 6
          r = hex[0..1].to_i(16) / 255.0
          g = hex[2..3].to_i(16) / 255.0
          b = hex[4..5].to_i(16) / 255.0
          a = hex.size >= 8 ? hex[6..7].to_i(16) / 255.0 : 1.0
          {r, g, b, a}
        end

        private def register_draw_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas_clear", 2) do |args|
            id, color = args[0].as_s, args[1].as_s
            r, g, b, a = Canvas.parse_hex(color)
            State.get(id).draw_commands << ClearCommand.new(r, g, b, a)
            nil
          end

          sandbox.bind("__canvas_fillRect", 6) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[5].as_s)
            State.get(id).draw_commands << FillRectCommand.new(
              args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, r, g, b, a
            )
            nil
          end

          sandbox.bind("__canvas_strokeRect", 7) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[5].as_s)
            State.get(id).draw_commands << StrokeRectCommand.new(
              args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, r, g, b, a, args[6].as_f64
            )
            nil
          end

          sandbox.bind("__canvas_fillCircle", 5) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[4].as_s)
            State.get(id).draw_commands << FillCircleCommand.new(
              args[1].as_f64, args[2].as_f64, args[3].as_f64, r, g, b, a
            )
            nil
          end

          sandbox.bind("__canvas_strokeCircle", 6) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[4].as_s)
            State.get(id).draw_commands << StrokeCircleCommand.new(
              args[1].as_f64, args[2].as_f64, args[3].as_f64, r, g, b, a, args[5].as_f64
            )
            nil
          end

          sandbox.bind("__canvas_drawLine", 7) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[5].as_s)
            State.get(id).draw_commands << DrawLineCommand.new(
              args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, r, g, b, a, args[6].as_f64
            )
            nil
          end

          sandbox.bind("__canvas_fillText", 6) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[4].as_s)
            State.get(id).draw_commands << FillTextCommand.new(
              args[1].as_s, args[2].as_f64, args[3].as_f64, r, g, b, a, args[5].as_f64
            )
            nil
          end

          sandbox.bind("__canvas_fillTriangle", 8) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[7].as_s)
            State.get(id).draw_commands << FillTriangleCommand.new(
              args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64,
              args[5].as_f64, args[6].as_f64, r, g, b, a
            )
            nil
          end

          sandbox.bind("__canvas_isKeyDown", 2) do |args|
            State.get(args[0].as_s).keys_held.includes?(args[1].as_s)
          end

          sandbox.bind("__canvas_getMouseX", 1) do |args|
            State.get(args[0].as_s).mouse_x
          end

          sandbox.bind("__canvas_getMouseY", 1) do |args|
            State.get(args[0].as_s).mouse_y
          end

          sandbox.bind("__canvas_isMouseDown", 1) do |args|
            State.get(args[0].as_s).mouse_down
          end

          sandbox.bind("__canvas_getWidth", 1) do |args|
            id = args[0].as_s
            if c = Registry.instance.registered_components[id]?
              c.widget.as(Gtk::GLArea).allocated_width.to_f64
            else
              State.get(id).width.to_f64
            end
          end

          sandbox.bind("__canvas_getHeight", 1) do |args|
            id = args[0].as_s
            if c = Registry.instance.registered_components[id]?
              c.widget.as(Gtk::GLArea).allocated_height.to_f64
            else
              State.get(id).height.to_f64
            end
          end
        end

        private def register_control_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas_start", 1) do |args|
            @@active_canvas_id = args[0].as_s
            state = State.get(@@active_canvas_id.not_nil!)
            state.running = true
            @@active_interval = (1000 / state.frames_per_second).to_u32

            LibGLib.g_timeout_add_full(
              0, @@active_interval,
              ->(data : Pointer(Void)) {
                id = @@active_canvas_id
                return 0 unless id

                cs = State.get(id)
                return 0 unless cs.running

                begin
                  Engine.instance.sandbox.eval_mutex!(
                    "if (typeof __canvasCallbacks !== 'undefined' && __canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onUpdate) {\n" \
                    "  __canvasCallbacks['#{id}'].onUpdate(#{@@active_interval / 1000.0});\n" \
                    "}\n"
                  )
                rescue
                end

                begin
                  cs.draw_commands.clear
                  Engine.instance.sandbox.eval_mutex!(
                    "if (typeof __canvasCallbacks !== 'undefined' && __canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onDraw) {\n" \
                    "  __canvasCallbacks['#{id}'].onDraw(__canvasContexts['#{id}']);\n" \
                    "}\n"
                  )
                rescue
                end

                c = Registry.instance.registered_components[id]?
                c.try(&.widget.as(Gtk::GLArea).queue_render)

                cs.running ? 1 : 0
              }.pointer,
              Pointer(Void).null,
              Pointer(Void).null
            )
            nil
          end

          sandbox.bind("__canvas_stop", 1) do |args|
            State.get(args[0].as_s).running = false
            nil
          end
        end

        private def install_js_module(sandbox) : Nil
          # The game loop (Crystal-side g_timeout callback) calls into JS via eval_mutex!
          # using these global lookup tables. They must exist in the global scope so the
          # eval'd strings can find them. The ES module itself populates them.
          sandbox.eval_mutex!(<<-JS)
            globalThis.__canvasCallbacks = {};
            globalThis.__canvasContexts = {};
          JS

          ModuleLoader.register("canvas", <<-JS)
            class Canvas {
              constructor(id, opts) {
                opts = opts || {};
                this.id = id;
                this.width = opts.width || 800;
                this.height = opts.height || 600;
                this.framesPerSecond = opts.framesPerSecond || 60;

                __canvasCallbacks[id] = {};

                __canvasContexts[id] = {
                  clear(color)                          { __canvas_clear(id, color || '#000000'); },
                  fillRect(x, y, w, h, color)           { __canvas_fillRect(id, x, y, w, h, color || '#ffffff'); },
                  strokeRect(x, y, w, h, color, lw)     { __canvas_strokeRect(id, x, y, w, h, color || '#ffffff', lw || 1); },
                  fillCircle(x, y, r, color)             { __canvas_fillCircle(id, x, y, r, color || '#ffffff'); },
                  strokeCircle(x, y, r, color, lw)       { __canvas_strokeCircle(id, x, y, r, color || '#ffffff', lw || 1); },
                  drawLine(x1, y1, x2, y2, color, lw)   { __canvas_drawLine(id, x1, y1, x2, y2, color || '#ffffff', lw || 1); },
                  fillText(text, x, y, color, size)      { __canvas_fillText(id, text, x, y, color || '#ffffff', size || 16); },
                  fillTriangle(x1, y1, x2, y2, x3, y3, color) { __canvas_fillTriangle(id, x1, y1, x2, y2, x3, y3, color || '#ffffff'); }
                };
              }

              onDraw(cb)      { __canvasCallbacks[this.id].onDraw = cb; }
              onUpdate(cb)    { __canvasCallbacks[this.id].onUpdate = cb; }
              onKeyDown(cb)   { __canvasCallbacks[this.id].onKeyDown = cb; }
              onKeyUp(cb)     { __canvasCallbacks[this.id].onKeyUp = cb; }
              onMouseDown(cb) { __canvasCallbacks[this.id].onMouseDown = cb; }
              onMouseUp(cb)   { __canvasCallbacks[this.id].onMouseUp = cb; }
              onMouseMove(cb) { __canvasCallbacks[this.id].onMouseMove = cb; }

              isKeyDown(key)  { return __canvas_isKeyDown(this.id, key); }
              mouseX()        { return __canvas_getMouseX(this.id); }
              mouseY()        { return __canvas_getMouseY(this.id); }
              isMouseDown()   { return __canvas_isMouseDown(this.id); }

              getWidth()      { return __canvas_getWidth(this.id); }
              getHeight()     { return __canvas_getHeight(this.id); }

              start() { __canvas_start(this.id); }
              stop()  { __canvas_stop(this.id); }
            }

            export { Canvas };
          JS
        end

        # Called by __create_widget when kind == "Canvas"
        def self.create_widget(id : String, props : JSON::Any) : Gtk::GLArea
          state = State.get(id)
          state.width = (props["width"]?.try(&.as_i?) || props["width"]?.try(&.as_s.to_i?)) || 800
          state.height = (props["height"]?.try(&.as_i?) || props["height"]?.try(&.as_s.to_i?)) || 600
          state.frames_per_second = (props["framesPerSecond"]?.try(&.as_i?) || props["framesPerSecond"]?.try(&.as_s.to_i?)) || 60

          gl_area = Gtk::GLArea.new
          gl_area.set_size_request(state.width, state.height)
          gl_area.auto_render = false
          gl_area.focusable = true
          gl_area.can_focus = true

          gl_area.realize_signal.connect do
            gl_area.make_current
            state.renderer.initialize_gl
            state.text_renderer.setup(gl_area)
          end

          gl_area.render_signal.connect do |context|
            renderer = state.renderer
            next true unless renderer.initialized?

            scale = gl_area.scale_factor
            w = gl_area.allocated_width
            h = gl_area.allocated_height

            renderer.begin_frame(w * scale, h * scale, w, h)

            state.draw_commands.each do |cmd|
              case cmd
              when ClearCommand
                renderer.clear(cmd.r.to_f32, cmd.g.to_f32, cmd.b.to_f32, cmd.a.to_f32)
              when FillRectCommand
                renderer.fill_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.r, cmd.g, cmd.b, cmd.a)
              when StrokeRectCommand
                renderer.stroke_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
              when FillCircleCommand
                renderer.fill_circle(cmd.x, cmd.y, cmd.radius, cmd.r, cmd.g, cmd.b, cmd.a)
              when StrokeCircleCommand
                renderer.stroke_circle(cmd.x, cmd.y, cmd.radius, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
              when DrawLineCommand
                renderer.draw_line(cmd.x1, cmd.y1, cmd.x2, cmd.y2, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
              when FillTriangleCommand
                renderer.fill_triangle(cmd.x1, cmd.y1, cmd.x2, cmd.y2, cmd.x3, cmd.y3, cmd.r, cmd.g, cmd.b, cmd.a)
              when FillTextCommand
                state.text_renderer.render(renderer, cmd.text, cmd.x, cmd.y, cmd.r, cmd.g, cmd.b, cmd.a, cmd.size)
              end
            end

            state.text_renderer.tick
            renderer.end_frame
            true
          end

          # Keyboard
          key_controller = Gtk::EventControllerKey.new
          key_controller.key_pressed_signal.connect do |key_val, _, _|
            canvas = State.get(id)
            key_name = Gdk.keyval_name(key_val) || key_val.to_s
            canvas.keys_held.add(key_name)
            begin
              Engine.instance.sandbox.eval_mutex!(
                "if (__canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onKeyDown) {\n" \
                "  __canvasCallbacks['#{id}'].onKeyDown('#{key_name}');\n" \
                "}\n"
              )
            rescue
            end
            true
          end
          key_controller.key_released_signal.connect do |key_val, _, _|
            canvas = State.get(id)
            key_name = Gdk.keyval_name(key_val) || key_val.to_s
            canvas.keys_held.delete(key_name)
            begin
              Engine.instance.sandbox.eval_mutex!(
                "if (__canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onKeyUp) {\n" \
                "  __canvasCallbacks['#{id}'].onKeyUp('#{key_name}');\n" \
                "}\n"
              )
            rescue
            end
          end
          gl_area.add_controller(key_controller)

          # Mouse
          motion = Gtk::EventControllerMotion.new
          motion.motion_signal.connect do |x, y|
            canvas = State.get(id)
            canvas.mouse_x = x
            canvas.mouse_y = y
            begin
              Engine.instance.sandbox.eval_mutex!(
                "if (__canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onMouseMove) {\n" \
                "  __canvasCallbacks['#{id}'].onMouseMove(#{x}, #{y});\n" \
                "}\n"
              )
            rescue
            end
          end
          gl_area.add_controller(motion)

          click = Gtk::GestureClick.new
          click.pressed_signal.connect do |_, x, y|
            canvas = State.get(id)
            canvas.mouse_down = true
            gl_area.grab_focus
            begin
              Engine.instance.sandbox.eval_mutex!(
                "if (__canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onMouseDown) {\n" \
                "  __canvasCallbacks['#{id}'].onMouseDown(#{x}, #{y});\n" \
                "}\n"
              )
            rescue
            end
          end
          click.released_signal.connect do |_, x, y|
            State.get(id).mouse_down = false
            begin
              Engine.instance.sandbox.eval_mutex!(
                "if (__canvasCallbacks['#{id}'] && __canvasCallbacks['#{id}'].onMouseUp) {\n" \
                "  __canvasCallbacks['#{id}'].onMouseUp(#{x}, #{y});\n" \
                "}\n"
              )
            rescue
            end
          end
          gl_area.add_controller(click)

          gl_area
        end
      end
    end
  end
end
