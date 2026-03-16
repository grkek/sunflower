# 2D/3D game engine module using OpenGL via GTK4's GLArea.
# All rendering is batched and GPU-accelerated.
#
# The STD lib module name stays as `Canvas`.
# Internal rendering is delegated to Petal::Renderers and Petal::Renderer3D.
#
# JS API:
#   import { Canvas, Canvas3D } from "canvas";
#
#   // 2D (unchanged)
#   const canvas = new Canvas("game", { width: 800, height: 500, framesPerSecond: 60 });
#
#   canvas.onDraw((context) => { context.clear("#000"); context.fillRect(10, 10, 50, 50, "#f00"); });
#   canvas.onUpdate((dt) => { if (canvas.isKeyDown("w")) { ... } });
#   canvas.start();
#
#   // 3D
#   const scene = new Canvas3D("scene", { width: 800, height: 600, framesPerSecond: 60 });
#
#   scene.setCamera({ position: [0,2,5], target: [0,0,0], fov: 60 });
#   scene.addLight({ type: "directional", direction: [0,-1,-1], color: "#ffffff", intensity: 1.0 });
#   const cube = scene.addMesh("cube", { size: 1 });
#   scene.onUpdate((dt) => { scene.rotateMesh(cube, 0, dt, 0); });
#   scene.start();

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
          property clear_color : Petal::Math::Color = Petal::Math::Color.white
          property running : Bool = false
          property draw_commands : Array(DrawCommand) = [] of DrawCommand
          property keys_held : Set(String) = Set(String).new
          property mouse_x : Float64 = 0.0
          property mouse_y : Float64 = 0.0
          property mouse_down : Bool = false

          # 2D rendering (Petal)
          property flat_renderer : Petal::Renderers::Flat::Renderer = Petal::Renderers::Flat::Renderer.new
          property text_renderer : Petal::Renderers::Flat::Text = Petal::Renderers::Flat::Text.new

          # 3D rendering (Petal) — nil unless this is a Canvas3D instance
          property dimensional_renderer : Petal::Renderers::Dimensional::Renderer? = nil
          property mode : Symbol = :mode_2d # :mode_2d or :mode_3d

          @@canvases = {} of String => State

          def self.get(id : String) : State
            @@canvases[id] ||= State.new
          end

          def self.remove(id : String)
            if state = @@canvases.delete(id)
              state.flat_renderer.cleanup
              state.dimensional_renderer.try(&.cleanup)
            end
          end
        end

        # Draw commands (2D)

        abstract struct DrawCommand; end

        struct ClearCommand < DrawCommand
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64

          def initialize(@r, @g, @b, @a); end
        end

        struct FillRectCommand < DrawCommand
          getter x : Float64; getter y : Float64; getter w : Float64; getter h : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64

          def initialize(@x, @y, @w, @h, @r, @g, @b, @a); end
        end

        struct StrokeRectCommand < DrawCommand
          getter x : Float64; getter y : Float64; getter w : Float64; getter h : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64
          getter line_width : Float64

          def initialize(@x, @y, @w, @h, @r, @g, @b, @a, @line_width); end
        end

        struct FillCircleCommand < DrawCommand
          getter x : Float64; getter y : Float64; getter radius : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64

          def initialize(@x, @y, @radius, @r, @g, @b, @a); end
        end

        struct StrokeCircleCommand < DrawCommand
          getter x : Float64; getter y : Float64; getter radius : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64
          getter line_width : Float64

          def initialize(@x, @y, @radius, @r, @g, @b, @a, @line_width); end
        end

        struct DrawLineCommand < DrawCommand
          getter x1 : Float64; getter y1 : Float64; getter x2 : Float64; getter y2 : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64
          getter line_width : Float64

          def initialize(@x1, @y1, @x2, @y2, @r, @g, @b, @a, @line_width); end
        end

        struct FillTextCommand < DrawCommand
          getter text : String; getter x : Float64; getter y : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64
          getter size : Float64

          def initialize(@text, @x, @y, @r, @g, @b, @a, @size); end
        end

        struct FillTriangleCommand < DrawCommand
          getter x1 : Float64; getter y1 : Float64; getter x2 : Float64; getter y2 : Float64
          getter x3 : Float64; getter y3 : Float64
          getter r : Float64; getter g : Float64; getter b : Float64; getter a : Float64

          def initialize(@x1, @y1, @x2, @y2, @x3, @y3, @r, @g, @b, @a); end
        end

        def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
          register_draw_bindings(sandbox, engine)
          register_3d_bindings(sandbox, engine)
          register_control_bindings(sandbox, engine)
          install_js_module(sandbox)
        end

        def self.parse_hex(hex : String) : {Float64, Float64, Float64, Float64}
          c = Petal::Math::Color.from_hex(hex)
          {c.r, c.g, c.b, c.a}
        end

        # 2D draw bindings (unchanged API)

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

        # 3D bindings

        private def register_3d_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_init", 1) do |args|
            id = args[0].as_s
            state = State.get(id)
            state.mode = :mode_3d
            state.dimensional_renderer = Petal::Renderers::Dimensional::Renderer.new

            if c = Registry.instance.registered_components[id]?
              gl_area = c.widget.as(Gtk::GLArea)
              gl_area.make_current
              state.dimensional_renderer.try(&.initialize_gl)
            end

            nil
          end

          sandbox.bind("__canvas3d_setCamera", 10) do |args|
            id = args[0].as_s
            state = State.get(id)
            if r3d = state.dimensional_renderer
              r3d.camera.position = Petal::Math::Vector3.new(args[1].as_f64, args[2].as_f64, args[3].as_f64)
              r3d.camera.target = Petal::Math::Vector3.new(args[4].as_f64, args[5].as_f64, args[6].as_f64)
              r3d.camera.fov = Petal::Math.deg_to_rad(args[7].as_f64)
              r3d.camera.near = args[8].as_f64
              r3d.camera.far = args[9].as_f64
            end
            nil
          end

          sandbox.bind("__canvas3d_setCameraOrthographic", 3) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              r3d.camera.orthographic = args[1].as_s == "true"
              r3d.camera.ortho_size = args[2].as_f64
            end
            nil
          end

          sandbox.bind("__canvas3d_orbitCamera", 3) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              r3d.camera.orbit(args[1].as_f64, args[2].as_f64)
            end
            nil
          end

          sandbox.bind("__canvas3d_zoomCamera", 2) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              r3d.camera.zoom(args[1].as_f64)
            end
            nil
          end

          # addLight(id, type, posX, posY, posZ, dirX, dirY, dirZ, colorHex, intensity)
          sandbox.bind("__canvas3d_addLight", 10) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              type_str = args[1].as_s
              pos = Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              dir = Petal::Math::Vector3.new(args[5].as_f64, args[6].as_f64, args[7].as_f64)
              color = Petal::Math::Color.from_hex(args[8].as_s)
              intensity = args[9].as_f64

              light = case type_str
                      when "point"
                        Petal::Renderers::Dimensional::Light.point(pos, color, intensity)
                      when "spot"
                        Petal::Renderers::Dimensional::Light.spot(pos, dir, color, intensity)
                      else
                        Petal::Renderers::Dimensional::Light.directional(dir, color, intensity)
                      end
              r3d.add_light(light)
            end
            nil
          end

          sandbox.bind("__canvas3d_setAmbient", 2) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              r3d.ambient_light = Petal::Math::Color.from_hex(args[1].as_s)
            end
            nil
          end

          # addMesh(id, meshName, type, jsonParams) → returns mesh name
          sandbox.bind("__canvas3d_addMesh", 4) do |args|
            id = args[0].as_s
            mesh_name = args[1].as_s
            mesh_type = args[2].as_s
            params = JSON.parse(args[3].as_s)

            if r3d = State.get(id).dimensional_renderer
              color_hex = params["color"]?.try(&.as_s?) || "#ffffff"
              color = Petal::Math::Color.from_hex(color_hex)

              mesh = case mesh_type
                     when "cube"
                       Petal::Renderers::Dimensional::Mesh.cube(size: params["size"]?.try(&.as_f?) || 1.0, color: color)
                     when "sphere"
                       Petal::Renderers::Dimensional::Mesh.sphere(
                         radius: params["radius"]?.try(&.as_f?) || 1.0,
                         rings: (params["rings"]?.try(&.as_i?) || 16),
                         sectors: (params["sectors"]?.try(&.as_i?) || 32),
                         color: color
                       )
                     when "plane"
                       Petal::Renderers::Dimensional::Mesh.plane(
                         width: params["width"]?.try(&.as_f?) || 10.0,
                         depth: params["depth"]?.try(&.as_f?) || 10.0,
                         color: color
                       )
                     when "cylinder"
                       Petal::Renderers::Dimensional::Mesh.cylinder(
                         radius: params["radius"]?.try(&.as_f?) || 0.5,
                         height: params["height"]?.try(&.as_f?) || 1.0,
                         color: color
                       )
                     when "cone"
                       Petal::Renderers::Dimensional::Mesh.cone(
                         radius: params["radius"]?.try(&.as_f?) || 0.5,
                         height: params["height"]?.try(&.as_f?) || 1.0,
                         color: color
                       )
                     else
                       Petal::Renderers::Dimensional::Mesh.cube(color: color)
                     end

              node = Petal::Renderers::Dimensional::SceneNode.new(name: mesh_name, mesh: mesh)

              if pos = params["position"]?.try(&.as_a?)
                node.transform.position = Petal::Math::Vector3.new(
                  pos[0]?.try(&.as_f?) || 0.0,
                  pos[1]?.try(&.as_f?) || 0.0,
                  pos[2]?.try(&.as_f?) || 0.0
                )
              end

              if scale = params["scale"]?.try(&.as_a?)
                node.transform.scale = Petal::Math::Vector3.new(
                  scale[0]?.try(&.as_f?) || 1.0,
                  scale[1]?.try(&.as_f?) || 1.0,
                  scale[2]?.try(&.as_f?) || 1.0
                )
              end

              # Material
              if mat_data = params["material"]?
                mat = Petal::Renderers::Dimensional::Material.new
                if amb = mat_data["ambient"]?.try(&.as_s?)
                  c = Petal::Math::Color.from_hex(amb)
                  mat.ambient = c
                end
                if diff = mat_data["diffuse"]?.try(&.as_s?)
                  c = Petal::Math::Color.from_hex(diff)
                  mat.diffuse = c
                end
                if spec = mat_data["specular"]?.try(&.as_s?)
                  c = Petal::Math::Color.from_hex(spec)
                  mat.specular = c
                end
                if shin = mat_data["shininess"]?.try(&.as_f?)
                  mat.shininess = shin
                end
                node.material = mat
              end

              r3d.root.add_child(node)
            end

            mesh_name
          end

          # setMeshPosition(id, meshName, x, y, z)
          sandbox.bind("__canvas3d_setMeshPosition", 5) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              if node = r3d.root.find(args[1].as_s)
                node.transform.position = Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          # rotateMesh(id, meshName, pitch, yaw, roll)
          sandbox.bind("__canvas3d_rotateMesh", 5) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              if node = r3d.root.find(args[1].as_s)
                node.transform.rotate_euler(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          # setMeshScale(id, meshName, sx, sy, sz)
          sandbox.bind("__canvas3d_setMeshScale", 5) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              if node = r3d.root.find(args[1].as_s)
                node.transform.scale = Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          # setMeshVisible(id, meshName, visible)
          sandbox.bind("__canvas3d_setMeshVisible", 3) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              if node = r3d.root.find(args[1].as_s)
                node.visible = args[2].as_s == "true"
              end
            end
            nil
          end

          # removeMesh(id, meshName)
          sandbox.bind("__canvas3d_removeMesh", 2) do |args|
            id = args[0].as_s
            if r3d = State.get(id).dimensional_renderer
              if node = r3d.root.find(args[1].as_s)
                r3d.root.remove_child(node)
                node.mesh.try(&.cleanup)
              end
            end
            nil
          end

          # clear3D(id, colorHex)
          sandbox.bind("__canvas3d_clear", 2) do |args|
            State.get(args[0].as_s).clear_color = Petal::Math::Color.from_hex(args[1].as_s)
            nil
          end
        end

        # Control bindings (start/stop)
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

        # JS module installation
        private def install_js_module(sandbox) : Nil
          sandbox.eval_mutex!(<<-JS)
            globalThis.__canvasCallbacks = {};
            globalThis.__canvasContexts = {};
          JS

          ModuleLoader.register("canvas", <<-JS)
            // ═══════════════════════════════════════════════════
            //  Canvas (2D) — unchanged public API
            // ═══════════════════════════════════════════════════
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

            // ═══════════════════════════════════════════════════
            //  Canvas3D — new 3D API
            // ═══════════════════════════════════════════════════
            class Canvas3D {
              constructor(id, opts) {
                opts = opts || {};
                this.id = id;
                this.width = opts.width || 800;
                this.height = opts.height || 600;
                this.framesPerSecond = opts.framesPerSecond || 60;

                __canvas3d_init(id);
                __canvasCallbacks[id] = {};

                // 3D canvas still gets a 2D context overlay for HUD / debug text
                __canvasContexts[id] = {
                  clear(color)                          { __canvas3d_clear(id, color || '#000000'); },
                  fillRect(x, y, w, h, color)           { __canvas_fillRect(id, x, y, w, h, color || '#ffffff'); },
                  strokeRect(x, y, w, h, color, lw)     { __canvas_strokeRect(id, x, y, w, h, color || '#ffffff', lw || 1); },
                  fillCircle(x, y, r, color)             { __canvas_fillCircle(id, x, y, r, color || '#ffffff'); },
                  strokeCircle(x, y, r, color, lw)       { __canvas_strokeCircle(id, x, y, r, color || '#ffffff', lw || 1); },
                  drawLine(x1, y1, x2, y2, color, lw)   { __canvas_drawLine(id, x1, y1, x2, y2, color || '#ffffff', lw || 1); },
                  fillText(text, x, y, color, size)      { __canvas_fillText(id, text, x, y, color || '#ffffff', size || 16); },
                  fillTriangle(x1, y1, x2, y2, x3, y3, color) { __canvas_fillTriangle(id, x1, y1, x2, y2, x3, y3, color || '#ffffff'); }
                };
              }

              // ── Camera ──
              setCamera(opts) {
                const p = opts.position || [0, 0, 5];
                const t = opts.target || [0, 0, 0];
                const fov = opts.fov || 60;
                const near = opts.near || 0.1;
                const far = opts.far || 1000;
                __canvas3d_setCamera(this.id, p[0], p[1], p[2], t[0], t[1], t[2], fov, near, far);
              }
              setCameraOrthographic(enabled, size) {
                __canvas3d_setCameraOrthographic(this.id, enabled ? "true" : "false", size || 10);
              }
              orbitCamera(yaw, pitch) { __canvas3d_orbitCamera(this.id, yaw, pitch); }
              zoomCamera(amount)      { __canvas3d_zoomCamera(this.id, amount); }

              // ── Lighting ──
              addLight(opts) {
                const type = opts.type || "directional";
                const pos = opts.position || [0, 0, 0];
                const dir = opts.direction || [0, -1, 0];
                const color = opts.color || "#ffffff";
                const intensity = opts.intensity || 1.0;
                __canvas3d_addLight(this.id, type, pos[0], pos[1], pos[2], dir[0], dir[1], dir[2], color, intensity);
              }
              setAmbient(color) { __canvas3d_setAmbient(this.id, color || "#1a1a1a"); }

              // ── Mesh management ──
              addMesh(name, type, opts) {
                opts = opts || {};
                return __canvas3d_addMesh(this.id, name, type || "cube", JSON.stringify(opts));
              }
              setMeshPosition(name, x, y, z)  { __canvas3d_setMeshPosition(this.id, name, x, y, z); }
              rotateMesh(name, pitch, yaw, roll) { __canvas3d_rotateMesh(this.id, name, pitch, yaw, roll); }
              setMeshScale(name, sx, sy, sz)  { __canvas3d_setMeshScale(this.id, name, sx, sy, sz); }
              setMeshVisible(name, visible)   { __canvas3d_setMeshVisible(this.id, name, visible ? "true" : "false"); }
              removeMesh(name)                { __canvas3d_removeMesh(this.id, name); }

              // ── Callbacks ──
              onDraw(cb)      { __canvasCallbacks[this.id].onDraw = cb; }
              onUpdate(cb)    { __canvasCallbacks[this.id].onUpdate = cb; }
              onKeyDown(cb)   { __canvasCallbacks[this.id].onKeyDown = cb; }
              onKeyUp(cb)     { __canvasCallbacks[this.id].onKeyUp = cb; }
              onMouseDown(cb) { __canvasCallbacks[this.id].onMouseDown = cb; }
              onMouseUp(cb)   { __canvasCallbacks[this.id].onMouseUp = cb; }
              onMouseMove(cb) { __canvasCallbacks[this.id].onMouseMove = cb; }

              // ── Input ──
              isKeyDown(key)  { return __canvas_isKeyDown(this.id, key); }
              mouseX()        { return __canvas_getMouseX(this.id); }
              mouseY()        { return __canvas_getMouseY(this.id); }
              isMouseDown()   { return __canvas_isMouseDown(this.id); }

              getWidth()      { return __canvas_getWidth(this.id); }
              getHeight()     { return __canvas_getHeight(this.id); }

              start() { __canvas_start(this.id); }
              stop()  { __canvas_stop(this.id); }
            }

            export { Canvas, Canvas3D };
          JS
        end

        # Widget creation
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

          gl_area.has_depth_buffer = true

          gl_area.realize_signal.connect do
            gl_area.make_current
            state.flat_renderer.initialize_gl
            state.text_renderer.setup(gl_area)
            state.dimensional_renderer.try(&.initialize_gl)
          end

          gl_area.render_signal.connect do |context|
            if state.mode == :mode_3d
              render_3d_frame(state, gl_area)
            else
              render_2d_frame(state, gl_area)
            end

            true
          end

          attach_input_controllers(id, gl_area)

          gl_area
        end

        private def self.render_2d_frame(state : State, gl_area : Gtk::GLArea) : Nil
          renderer = state.flat_renderer
          return unless renderer.initialized?

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
        end

        private def self.render_3d_frame(state : State, gl_area : Gtk::GLArea) : Nil
          r3d = state.dimensional_renderer
          return unless r3d && r3d.initialized?

          scale = gl_area.scale_factor
          w = gl_area.allocated_width
          h = gl_area.allocated_height

          r3d.begin_frame(w * scale, h * scale)
          r3d.clear(state.clear_color)
          r3d.render_scene(w, h)
          r3d.end_frame

          # 2D overlay (HUD) — draw any 2D commands on top
          unless state.draw_commands.empty?
            flat_renderer = state.flat_renderer
            if flat_renderer.initialized?
              flat_renderer.begin_frame(w * scale, h * scale, w, h)
              state.draw_commands.each do |cmd|
                case cmd
                when FillRectCommand
                  flat_renderer.fill_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.r, cmd.g, cmd.b, cmd.a)
                when FillTextCommand
                  state.text_renderer.render(flat_renderer, cmd.text, cmd.x, cmd.y, cmd.r, cmd.g, cmd.b, cmd.a, cmd.size)
                when FillCircleCommand
                  flat_renderer.fill_circle(cmd.x, cmd.y, cmd.radius, cmd.r, cmd.g, cmd.b, cmd.a)
                when DrawLineCommand
                  flat_renderer.draw_line(cmd.x1, cmd.y1, cmd.x2, cmd.y2, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
                end
              end
              state.text_renderer.tick
              flat_renderer.end_frame
            end
          end
        end

        private def self.attach_input_controllers(id : String, gl_area : Gtk::GLArea) : Nil
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

          # Mouse motion
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

          # Mouse click
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
        end
      end
    end
  end
end
