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

          property flat_renderer : Petal::Renderers::Flat::Renderer = Petal::Renderers::Flat::Renderer.new
          property text_renderer : Petal::Renderers::Flat::Text = Petal::Renderers::Flat::Text.new

          property scene_renderer : Petal::Renderers::Dimensional::SceneRenderer? = nil
          property scene : Petal::Renderers::Dimensional::Scene? = nil
          property camera : Petal::Renderers::Dimensional::Camera? = nil
          property orbit_controls : Petal::Renderers::Dimensional::OrbitControls? = nil
          property animation_mixer : Petal::Renderers::Dimensional::AnimationMixer? = nil
          property clock : Petal::Renderers::Dimensional::Clock? = nil
          property raycaster : Petal::Renderers::Dimensional::Raycaster? = nil
          property texture_loader : Petal::Renderers::Dimensional::TextureLoader? = nil

          property mode : Symbol = :mode_2d

          @@canvases = {} of String => State

          def self.get(id : String) : State
            @@canvases[id] ||= State.new
          end

          def self.remove(id : String)
            if state = @@canvases.delete(id)
              state.flat_renderer.cleanup
              state.scene_renderer.try(&.cleanup)
              state.texture_loader.try(&.cleanup)
            end
          end
        end

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
          register_3d_material_bindings(sandbox, engine)
          register_3d_group_bindings(sandbox, engine)
          register_3d_scene_bindings(sandbox, engine)
          register_3d_interaction_bindings(sandbox, engine)
          register_3d_loader_bindings(sandbox, engine)
          register_control_bindings(sandbox, engine)
          install_js_module(sandbox)
        end

        def self.parse_hex(hex : String) : {Float64, Float64, Float64, Float64}
          c = Petal::Math::Color.from_hex(hex)
          {c.r, c.g, c.b, c.a}
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
            State.get(id).draw_commands << FillRectCommand.new(args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, r, g, b, a)
            nil
          end

          sandbox.bind("__canvas_strokeRect", 7) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[5].as_s)
            State.get(id).draw_commands << StrokeRectCommand.new(args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, r, g, b, a, args[6].as_f64)
            nil
          end

          sandbox.bind("__canvas_fillCircle", 5) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[4].as_s)
            State.get(id).draw_commands << FillCircleCommand.new(args[1].as_f64, args[2].as_f64, args[3].as_f64, r, g, b, a)
            nil
          end

          sandbox.bind("__canvas_strokeCircle", 6) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[4].as_s)
            State.get(id).draw_commands << StrokeCircleCommand.new(args[1].as_f64, args[2].as_f64, args[3].as_f64, r, g, b, a, args[5].as_f64)
            nil
          end

          sandbox.bind("__canvas_drawLine", 7) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[5].as_s)
            State.get(id).draw_commands << DrawLineCommand.new(args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, r, g, b, a, args[6].as_f64)
            nil
          end

          sandbox.bind("__canvas_fillText", 6) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[4].as_s)
            State.get(id).draw_commands << FillTextCommand.new(args[1].as_s, args[2].as_f64, args[3].as_f64, r, g, b, a, args[5].as_f64)
            nil
          end

          sandbox.bind("__canvas_fillTriangle", 8) do |args|
            id = args[0].as_s
            r, g, b, a = Canvas.parse_hex(args[7].as_s)
            State.get(id).draw_commands << FillTriangleCommand.new(args[1].as_f64, args[2].as_f64, args[3].as_f64, args[4].as_f64, args[5].as_f64, args[6].as_f64, r, g, b, a)
            nil
          end

          sandbox.bind("__canvas_isKeyDown", 2) do |args|
            State.get(args[0].as_s).keys_held.includes?(args[1].as_s)
          end

          sandbox.bind("__canvas_getMouseX", 1) { |args| State.get(args[0].as_s).mouse_x }
          sandbox.bind("__canvas_getMouseY", 1) { |args| State.get(args[0].as_s).mouse_y }
          sandbox.bind("__canvas_isMouseDown", 1) { |args| State.get(args[0].as_s).mouse_down }

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

        private def register_3d_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_init", 1) do |args|
            id = args[0].as_s
            state = State.get(id)
            state.mode = :mode_3d

            state.scene = Petal::Renderers::Dimensional::Scene.new
            state.camera = Petal::Renderers::Dimensional::Camera.new
            state.scene_renderer = Petal::Renderers::Dimensional::SceneRenderer.new
            state.animation_mixer = Petal::Renderers::Dimensional::AnimationMixer.new
            state.clock = Petal::Renderers::Dimensional::Clock.new
            state.raycaster = Petal::Renderers::Dimensional::Raycaster.new
            state.texture_loader = Petal::Renderers::Dimensional::TextureLoader.new

            if c = Registry.instance.registered_components[id]?
              gl_area = c.widget.as(Gtk::GLArea)
              gl_area.make_current
              state.scene_renderer.try(&.initialize_gl)
            end

            nil
          end

          sandbox.bind("__canvas3d_setCamera", 10) do |args|
            id = args[0].as_s
            if cam = State.get(id).camera
              cam.position = Petal::Math::Vector3.new(args[1].as_f64, args[2].as_f64, args[3].as_f64)
              cam.target = Petal::Math::Vector3.new(args[4].as_f64, args[5].as_f64, args[6].as_f64)
              cam.fov = Petal::Math.deg_to_rad(args[7].as_f64)
              cam.near = args[8].as_f64
              cam.far = args[9].as_f64
            end
            nil
          end

          sandbox.bind("__canvas3d_setCameraOrthographic", 3) do |args|
            id = args[0].as_s
            if cam = State.get(id).camera
              cam.orthographic = args[1].as_s == "true"
              cam.ortho_size = args[2].as_f64
            end
            nil
          end

          sandbox.bind("__canvas3d_orbitCamera", 3) do |args|
            id = args[0].as_s
            if cam = State.get(id).camera
              cam.orbit(args[1].as_f64, args[2].as_f64)
            end
            nil
          end

          sandbox.bind("__canvas3d_zoomCamera", 2) do |args|
            id = args[0].as_s
            if cam = State.get(id).camera
              cam.zoom(args[1].as_f64)
            end
            nil
          end

          sandbox.bind("__canvas3d_enableOrbitControls", 1) do |args|
            id = args[0].as_s
            state = State.get(id)
            if cam = state.camera
              state.orbit_controls = Petal::Renderers::Dimensional::OrbitControls.new(cam)
            end
            nil
          end

          sandbox.bind("__canvas3d_setOrbitTarget", 4) do |args|
            id = args[0].as_s
            if oc = State.get(id).orbit_controls
              oc.target = Petal::Math::Vector3.new(args[1].as_f64, args[2].as_f64, args[3].as_f64)
            end
            nil
          end

          sandbox.bind("__canvas3d_addLight", 10) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              type_str = args[1].as_s
              pos = Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              dir = Petal::Math::Vector3.new(args[5].as_f64, args[6].as_f64, args[7].as_f64)
              color = Petal::Math::Color.from_hex(args[8].as_s)
              intensity = args[9].as_f64

              light_obj = case type_str
                          when "point"
                            obj = Petal::Renderers::Dimensional::PointLightObject.new(color: color, intensity: intensity)
                            obj.position = pos
                            obj
                          when "spot"
                            obj = Petal::Renderers::Dimensional::SpotLightObject.new(color: color, intensity: intensity, target_position: pos + dir)
                            obj.position = pos
                            obj
                          when "hemisphere"
                            Petal::Renderers::Dimensional::HemisphereLightObject.new(sky_color: color, intensity: intensity)
                          else
                            obj = Petal::Renderers::Dimensional::DirectionalLightObject.new(color: color, intensity: intensity, direction: dir)
                            obj
                          end

              scene.add(light_obj)
            end
            nil
          end

          sandbox.bind("__canvas3d_setAmbient", 2) do |args|
            id = args[0].as_s
            state = State.get(id)
            if scene = state.scene
              scene.ambient_light_color = Petal::Math::Color.from_hex(args[1].as_s)
            end
            nil
          end

          sandbox.bind("__canvas3d_addAmbientLight", 3) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              color = Petal::Math::Color.from_hex(args[1].as_s)
              intensity = args[2].as_f64
              scene.add(Petal::Renderers::Dimensional::AmbientLightObject.new(color: color, intensity: intensity))
            end
            nil
          end

          sandbox.bind("__canvas3d_addMesh", 4) do |args|
            id = args[0].as_s
            mesh_name = args[1].as_s
            mesh_type = args[2].as_s
            params = JSON.parse(args[3].as_s)

            if scene = State.get(id).scene
              color_hex = params["color"]?.try(&.as_s?) || "#ffffff"
              color = Petal::Math::Color.from_hex(color_hex)

              geometry = Canvas.build_geometry(mesh_type, params)
              material = Canvas.build_material(params, color)

              mesh3d = Petal::Renderers::Dimensional::Mesh3D.new(geometry: geometry, material_base: material, name: mesh_name)

              if pos = params["position"]?.try(&.as_a?)
                mesh3d.position = Petal::Math::Vector3.new(
                  pos[0]?.try(&.as_f?) || 0.0, pos[1]?.try(&.as_f?) || 0.0, pos[2]?.try(&.as_f?) || 0.0
                )
              end

              if scale = params["scale"]?.try(&.as_a?)
                mesh3d.scale = Petal::Math::Vector3.new(
                  scale[0]?.try(&.as_f?) || 1.0, scale[1]?.try(&.as_f?) || 1.0, scale[2]?.try(&.as_f?) || 1.0
                )
              end

              parent_name = params["parent"]?.try(&.as_s?)
              if parent_name && (parent_obj = scene.find_by_name(parent_name))
                parent_obj.add(mesh3d)
              else
                scene.add(mesh3d)
              end
            end

            mesh_name
          end

          sandbox.bind("__canvas3d_setMeshPosition", 5) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              if node = scene.find_by_name(args[1].as_s)
                node.position = Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_rotateMesh", 5) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              if node = scene.find_by_name(args[1].as_s)
                node.transform.rotate_euler(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_setMeshScale", 5) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              if node = scene.find_by_name(args[1].as_s)
                node.scale = Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_setMeshVisible", 3) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              if node = scene.find_by_name(args[1].as_s)
                node.visible = args[2].as_s == "true"
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_removeMesh", 2) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              if node = scene.find_by_name(args[1].as_s)
                node.remove_from_parent
                if node.is_a?(Petal::Renderers::Dimensional::Mesh3D)
                  node.cleanup
                end
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_lookAt", 5) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              if node = scene.find_by_name(args[1].as_s)
                node.look_at(Petal::Math::Vector3.new(args[2].as_f64, args[3].as_f64, args[4].as_f64))
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_clear", 2) do |args|
            state = State.get(args[0].as_s)
            if scene = state.scene
              scene.background = Petal::Math::Color.from_hex(args[1].as_s)
            end
            state.clear_color = Petal::Math::Color.from_hex(args[1].as_s)
            nil
          end

          sandbox.bind("__canvas3d_getStats", 1) do |args|
            id = args[0].as_s
            if sr = State.get(id).scene_renderer
              stats = sr.stats
              "{\"drawCalls\":#{stats.draw_calls},\"triangles\":#{stats.triangles},\"rendered\":#{stats.objects_rendered},\"culled\":#{stats.objects_culled},\"frameMs\":#{stats.frame_time_ms.round(2)}}"
            else
              "{}"
            end
          end
        end

        private def register_3d_material_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_setMeshMaterial", 3) do |args|
            id = args[0].as_s
            mesh_name = args[1].as_s
            mat_json = JSON.parse(args[2].as_s)

            if scene = State.get(id).scene
              if node = scene.find_by_name(mesh_name)
                if node.is_a?(Petal::Renderers::Dimensional::Mesh3D)
                  color_hex = mat_json["color"]?.try(&.as_s?) || "#cccccc"
                  color = Petal::Math::Color.from_hex(color_hex)
                  node.material_base = Canvas.build_material(mat_json, color)
                end
              end
            end
            nil
          end
        end

        private def register_3d_group_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_addGroup", 2) do |args|
            id = args[0].as_s
            group_name = args[1].as_s
            if scene = State.get(id).scene
              group = Petal::Renderers::Dimensional::Group.new(name: group_name)
              scene.add(group)
            end
            group_name
          end

          sandbox.bind("__canvas3d_reparent", 3) do |args|
            id = args[0].as_s
            child_name = args[1].as_s
            parent_name = args[2].as_s
            if scene = State.get(id).scene
              child = scene.find_by_name(child_name)
              parent = scene.find_by_name(parent_name)
              if child && parent
                parent.attach(child)
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_addGridHelper", 3) do |args|
            id = args[0].as_s
            size = args[1].as_f64
            divisions = args[2].as_f64.to_i32
            if scene = State.get(id).scene
              grid = Petal::Renderers::Dimensional::GridHelper.new(size: size, divisions: divisions)
              scene.add(grid)
            end
            nil
          end

          sandbox.bind("__canvas3d_addAxesHelper", 2) do |args|
            id = args[0].as_s
            length = args[1].as_f64
            if scene = State.get(id).scene
              axes = Petal::Renderers::Dimensional::AxesHelper.new(length: length)
              scene.add(axes)
            end
            nil
          end
        end

        private def register_3d_scene_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_setFog", 5) do |args|
            id = args[0].as_s
            if scene = State.get(id).scene
              fog_type = args[1].as_s
              color = Petal::Math::Color.from_hex(args[2].as_s)
              if fog_type == "exp2"
                scene.fog = Petal::Renderers::Dimensional::FogParams.exp2(color, args[3].as_f64)
              else
                scene.fog = Petal::Renderers::Dimensional::FogParams.linear(color, args[3].as_f64, args[4].as_f64)
              end
            end
            nil
          end

          sandbox.bind("__canvas3d_clearFog", 1) do |args|
            if scene = State.get(args[0].as_s).scene
              scene.fog = nil
            end
            nil
          end

          sandbox.bind("__canvas3d_setFrustumCulling", 2) do |args|
            if sr = State.get(args[0].as_s).scene_renderer
              sr.enable_frustum_culling = args[1].as_s == "true"
            end
            nil
          end
        end

        private def register_3d_interaction_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_raycast", 3) do |args|
            id = args[0].as_s
            state = State.get(id)
            screen_x = args[1].as_f64
            screen_y = args[2].as_f64

            result = "[]"
            if (rc = state.raycaster) && (cam = state.camera) && (scene = state.scene)
              w = state.width
              h = state.height
              ndc_x, ndc_y = Petal::Renderers::Dimensional::Raycaster.screen_to_ndc(screen_x, screen_y, w, h)
              aspect = w.to_f64 / h.to_f64
              rc.set_from_camera(ndc_x, ndc_y, cam, aspect)
              hits = rc.intersect_objects(scene)
              parts = hits.first(10).map do |hit|
                "{\"name\":\"#{hit.object.name}\",\"distance\":#{hit.distance.round(4)},\"point\":[#{hit.point.x.round(4)},#{hit.point.y.round(4)},#{hit.point.z.round(4)}]}"
              end
              result = "[#{parts.join(",")}]"
            end
            result
          end

          sandbox.bind("__canvas3d_orbitMouseMove", 4) do |args|
            id = args[0].as_s
            if oc = State.get(id).orbit_controls
              oc.on_mouse_move(args[1].as_f64, args[2].as_f64, args[3].as_f64.to_i32)
            end
            nil
          end

          sandbox.bind("__canvas3d_orbitScroll", 2) do |args|
            if oc = State.get(args[0].as_s).orbit_controls
              oc.on_scroll(args[1].as_f64)
            end
            nil
          end
        end

        private def register_3d_loader_bindings(sandbox, engine) : Nil
          sandbox.bind("__canvas3d_loadOBJ", 4) do |args|
            id = args[0].as_s
            obj_name = args[1].as_s
            path = args[2].as_s
            mat_json = JSON.parse(args[3].as_s)

            state = State.get(id)
            scene = state.scene

            if scene
              loader = Petal::Renderers::Dimensional::OBJLoader.new

              color_hex = mat_json["color"]?.try(&.as_s?) || "#cccccc"
              color = Petal::Math::Color.from_hex(color_hex)
              material = Canvas.build_material(mat_json, color)

              group = loader.load_as_mesh(path, material)
              group.name = obj_name

              if pos = mat_json["position"]?.try(&.as_a?)
                group.position = Petal::Math::Vector3.new(
                  pos[0]?.try(&.as_f?) || 0.0, pos[1]?.try(&.as_f?) || 0.0, pos[2]?.try(&.as_f?) || 0.0
                )
              end

              if scale = mat_json["scale"]?.try(&.as_a?)
                group.scale = Petal::Math::Vector3.new(
                  scale[0]?.try(&.as_f?) || 1.0, scale[1]?.try(&.as_f?) || 1.0, scale[2]?.try(&.as_f?) || 1.0
                )
              end

              parent_name = mat_json["parent"]?.try(&.as_s?)
              if parent_name && (parent_obj = scene.find_by_name(parent_name))
                parent_obj.add(group)
              else
                scene.add(group)
              end
            end

            obj_name
          end

          sandbox.bind("__canvas3d_loadOBJString", 4) do |args|
            id = args[0].as_s
            obj_name = args[1].as_s
            obj_source = args[2].as_s
            mat_json = JSON.parse(args[3].as_s)

            state = State.get(id)
            scene = state.scene

            if scene
              loader = Petal::Renderers::Dimensional::OBJLoader.new
              models = loader.parse(obj_source)

              color_hex = mat_json["color"]?.try(&.as_s?) || "#cccccc"
              color = Petal::Math::Color.from_hex(color_hex)
              material = Canvas.build_material(mat_json, color)

              group = Petal::Renderers::Dimensional::Group.new(name: obj_name)
              models.each do |model|
                mesh = Petal::Renderers::Dimensional::Mesh3D.new(
                  geometry: model.geometry, material_base: material, name: model.name
                )
                group.add(mesh)
              end

              if pos = mat_json["position"]?.try(&.as_a?)
                group.position = Petal::Math::Vector3.new(
                  pos[0]?.try(&.as_f?) || 0.0, pos[1]?.try(&.as_f?) || 0.0, pos[2]?.try(&.as_f?) || 0.0
                )
              end

              if scale = mat_json["scale"]?.try(&.as_a?)
                group.scale = Petal::Math::Vector3.new(
                  scale[0]?.try(&.as_f?) || 1.0, scale[1]?.try(&.as_f?) || 1.0, scale[2]?.try(&.as_f?) || 1.0
                )
              end

              parent_name = mat_json["parent"]?.try(&.as_s?)
              if parent_name && (parent_obj = scene.find_by_name(parent_name))
                parent_obj.add(group)
              else
                scene.add(group)
              end
            end

            obj_name
          end

          sandbox.bind("__canvas3d_getObjectChildren", 2) do |args|
            id = args[0].as_s
            obj_name = args[1].as_s
            result = "[]"
            if scene = State.get(id).scene
              if node = scene.find_by_name(obj_name)
                names = node.children.map { |c| "\"#{c.name}\"" }
                result = "[#{names.join(",")}]"
              end
            end
            result
          end

          sandbox.bind("__canvas3d_getObjectPosition", 2) do |args|
            id = args[0].as_s
            obj_name = args[1].as_s
            result = "[0,0,0]"
            if scene = State.get(id).scene
              if node = scene.find_by_name(obj_name)
                p = node.world_position
                result = "[#{p.x},#{p.y},#{p.z}]"
              end
            end
            result
          end

          sandbox.bind("__canvas3d_cloneObject", 3) do |args|
            id = args[0].as_s
            source_name = args[1].as_s
            clone_name = args[2].as_s

            if scene = State.get(id).scene
              if source = scene.find_by_name(source_name)
                cloned = Canvas.clone_subtree(source, clone_name)
                scene.add(cloned)
              end
            end

            clone_name
          end
        end

        protected def self.clone_subtree(source : Petal::Renderers::Dimensional::Object3D, new_name : String) : Petal::Renderers::Dimensional::Object3D
          if source.is_a?(Petal::Renderers::Dimensional::Mesh3D)
            cloned = Petal::Renderers::Dimensional::Mesh3D.new(
              geometry: source.geometry,
              material_base: source.material_base,
              name: new_name,
            )
            cloned.position = source.position
            cloned.rotation = source.rotation
            cloned.scale = source.scale
            cloned.visible = source.visible
            source.children.each_with_index do |child, i|
              cloned.add(clone_subtree(child, "#{new_name}_child_#{i}"))
            end
            cloned
          else
            group = Petal::Renderers::Dimensional::Group.new(name: new_name)
            group.position = source.position
            group.rotation = source.rotation
            group.scale = source.scale
            group.visible = source.visible
            source.children.each_with_index do |child, i|
              group.add(clone_subtree(child, "#{new_name}_child_#{i}"))
            end
            group
          end
        end

        protected def self.build_geometry(mesh_type : String, params : JSON::Any) : Petal::Renderers::Dimensional::Geometry
          case mesh_type
          when "cube", "box"
            Petal::Renderers::Dimensional::BoxGeometry.new(
              width: params["width"]?.try(&.as_f?) || params["size"]?.try(&.as_f?) || 1.0,
              height: params["height"]?.try(&.as_f?) || params["size"]?.try(&.as_f?) || 1.0,
              depth: params["depth"]?.try(&.as_f?) || params["size"]?.try(&.as_f?) || 1.0,
            )
          when "sphere"
            Petal::Renderers::Dimensional::SphereGeometry.new(
              radius: params["radius"]?.try(&.as_f?) || 1.0,
              width_segments: (params["widthSegments"]?.try(&.as_i?) || params["sectors"]?.try(&.as_i?) || 32),
              height_segments: (params["heightSegments"]?.try(&.as_i?) || params["rings"]?.try(&.as_i?) || 16),
            )
          when "plane"
            Petal::Renderers::Dimensional::PlaneGeometry.new(
              width: params["width"]?.try(&.as_f?) || 10.0,
              height: params["depth"]?.try(&.as_f?) || params["height"]?.try(&.as_f?) || 10.0,
            )
          when "cylinder"
            Petal::Renderers::Dimensional::CylinderGeometry.new(
              radius_top: params["radiusTop"]?.try(&.as_f?) || params["radius"]?.try(&.as_f?) || 0.5,
              radius_bottom: params["radiusBottom"]?.try(&.as_f?) || params["radius"]?.try(&.as_f?) || 0.5,
              height: params["height"]?.try(&.as_f?) || 1.0,
              radial_segments: params["segments"]?.try(&.as_i?) || 32,
            )
          when "cone"
            Petal::Renderers::Dimensional::ConeGeometry.new(
              radius: params["radius"]?.try(&.as_f?) || 0.5,
              height: params["height"]?.try(&.as_f?) || 1.0,
            )
          when "torus"
            Petal::Renderers::Dimensional::TorusGeometry.new(
              radius: params["radius"]?.try(&.as_f?) || 1.0,
              tube: params["tube"]?.try(&.as_f?) || 0.4,
            )
          when "torusKnot"
            Petal::Renderers::Dimensional::TorusKnotGeometry.new(
              radius: params["radius"]?.try(&.as_f?) || 1.0,
              tube: params["tube"]?.try(&.as_f?) || 0.4,
            )
          when "ring"
            Petal::Renderers::Dimensional::RingGeometry.new(
              inner_radius: params["innerRadius"]?.try(&.as_f?) || 0.5,
              outer_radius: params["outerRadius"]?.try(&.as_f?) || 1.0,
            )
          when "icosahedron"
            Petal::Renderers::Dimensional::IcosahedronGeometry.new(
              radius: params["radius"]?.try(&.as_f?) || 1.0,
              detail: params["detail"]?.try(&.as_i?) || 0,
            )
          else
            Petal::Renderers::Dimensional::BoxGeometry.new
          end
        end

        protected def self.build_material(params : JSON::Any, color : Petal::Math::Color) : Petal::Renderers::Dimensional::MaterialBase
          mat_data = params["material"]?
          mat_type = mat_data.try(&.["type"]?.try(&.as_s?)) || params["materialType"]?.try(&.as_s?) || "phong"
          transparent = mat_data.try(&.["transparent"]?.try(&.as_bool?)) || false
          opacity = mat_data.try(&.["opacity"]?.try(&.as_f?)) || 1.0
          side_str = mat_data.try(&.["side"]?.try(&.as_s?)) || "front"
          wireframe = mat_data.try(&.["wireframe"]?.try(&.as_bool?)) || false

          side = case side_str
                 when "back"   then Petal::Renderers::Dimensional::Side::Back
                 when "double" then Petal::Renderers::Dimensional::Side::Double
                 else               Petal::Renderers::Dimensional::Side::Front
                 end

          mat_color = color
          if c = mat_data.try(&.["color"]?.try(&.as_s?))
            mat_color = Petal::Math::Color.from_hex(c)
          end

          material : Petal::Renderers::Dimensional::MaterialBase = case mat_type
          when "basic"
            Petal::Renderers::Dimensional::MeshBasicMaterial.new(
              color: mat_color,
              transparent: transparent,
              opacity: opacity,
              side: side,
              wireframe: wireframe,
            )
          when "lambert"
            ambient = mat_data.try(&.["ambient"]?.try(&.as_s?))
            Petal::Renderers::Dimensional::MeshLambertMaterial.new(
              color: mat_color,
              ambient: ambient ? Petal::Math::Color.from_hex(ambient) : Petal::Math::Color.new(0.2, 0.2, 0.2),
              transparent: transparent,
              opacity: opacity,
              side: side,
              wireframe: wireframe,
            )
          when "normal"
            Petal::Renderers::Dimensional::MeshNormalMaterial.new(
              transparent: transparent,
              opacity: opacity,
              side: side,
              wireframe: wireframe,
            )
          else
            ambient = mat_data.try(&.["ambient"]?.try(&.as_s?))
            specular = mat_data.try(&.["specular"]?.try(&.as_s?))
            shininess = mat_data.try(&.["shininess"]?.try(&.as_f?)) || 32.0
            Petal::Renderers::Dimensional::MeshPhongMaterial.new(
              color: mat_color,
              ambient: ambient ? Petal::Math::Color.from_hex(ambient) : Petal::Math::Color.new(0.2, 0.2, 0.2),
              specular: specular ? Petal::Math::Color.from_hex(specular) : Petal::Math::Color.new(1.0, 1.0, 1.0),
              shininess: shininess,
              transparent: transparent,
              opacity: opacity,
              side: side,
              wireframe: wireframe,
            )
          end

          material
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

                if oc = cs.orbit_controls
                  dt = cs.clock.try(&.delta) || (@@active_interval / 1000.0)
                  oc.update(dt)
                end

                cs.animation_mixer.try(&.update(cs.clock.try(&.delta) || (@@active_interval / 1000.0)))

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

            class Canvas3D {
              constructor(id, opts) {
                opts = opts || {};
                this.id = id;
                this.width = opts.width || 800;
                this.height = opts.height || 600;
                this.framesPerSecond = opts.framesPerSecond || 60;

                __canvas3d_init(id);
                __canvasCallbacks[id] = {};

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

              setCamera(opts) {
                const p = opts.position || [0, 0, 5];
                const t = opts.target || [0, 0, 0];
                __canvas3d_setCamera(this.id, p[0], p[1], p[2], t[0], t[1], t[2], opts.fov || 60, opts.near || 0.1, opts.far || 1000);
              }
              setCameraOrthographic(enabled, size) { __canvas3d_setCameraOrthographic(this.id, enabled ? "true" : "false", size || 10); }
              orbitCamera(yaw, pitch) { __canvas3d_orbitCamera(this.id, yaw, pitch); }
              zoomCamera(amount) { __canvas3d_zoomCamera(this.id, amount); }

              enableOrbitControls() { __canvas3d_enableOrbitControls(this.id); }
              setOrbitTarget(x, y, z) { __canvas3d_setOrbitTarget(this.id, x, y, z); }
              orbitScroll(delta) { __canvas3d_orbitScroll(this.id, delta); }

              addLight(opts) {
                const type = opts.type || "directional";
                const pos = opts.position || [0, 0, 0];
                const dir = opts.direction || [0, -1, 0];
                __canvas3d_addLight(this.id, type, pos[0], pos[1], pos[2], dir[0], dir[1], dir[2], opts.color || "#ffffff", opts.intensity || 1.0);
              }
              addAmbientLight(color, intensity) { __canvas3d_addAmbientLight(this.id, color || "#1a1a1a", intensity || 1.0); }
              setAmbient(color) { __canvas3d_setAmbient(this.id, color || "#1a1a1a"); }

              addMesh(name, type, opts) { return __canvas3d_addMesh(this.id, name, type || "cube", JSON.stringify(opts || {})); }
              setMeshPosition(name, x, y, z) { __canvas3d_setMeshPosition(this.id, name, x, y, z); }
              rotateMesh(name, pitch, yaw, roll) { __canvas3d_rotateMesh(this.id, name, pitch, yaw, roll); }
              setMeshScale(name, sx, sy, sz) { __canvas3d_setMeshScale(this.id, name, sx, sy, sz); }
              setMeshVisible(name, visible) { __canvas3d_setMeshVisible(this.id, name, visible ? "true" : "false"); }
              removeMesh(name) { __canvas3d_removeMesh(this.id, name); }
              setMeshMaterial(name, opts) { __canvas3d_setMeshMaterial(this.id, name, JSON.stringify(opts || {})); }
              lookAt(name, x, y, z) { __canvas3d_lookAt(this.id, name, x, y, z); }

              addGroup(name) { return __canvas3d_addGroup(this.id, name); }
              reparent(childName, parentName) { __canvas3d_reparent(this.id, childName, parentName); }

              addGridHelper(size, divisions) { __canvas3d_addGridHelper(this.id, size || 10, divisions || 10); }
              addAxesHelper(length) { __canvas3d_addAxesHelper(this.id, length || 1); }

              setFog(opts) {
                opts = opts || {};
                const type = opts.type || "linear";
                const color = opts.color || "#cccccc";
                __canvas3d_setFog(this.id, type, color, opts.near || opts.density || 10, opts.far || 100);
              }
              clearFog() { __canvas3d_clearFog(this.id); }
              setFrustumCulling(enabled) { __canvas3d_setFrustumCulling(this.id, enabled ? "true" : "false"); }

              raycast(screenX, screenY) { return JSON.parse(__canvas3d_raycast(this.id, screenX, screenY)); }
              getStats() { return JSON.parse(__canvas3d_getStats(this.id)); }

              loadOBJ(name, path, opts) { return __canvas3d_loadOBJ(this.id, name, path, JSON.stringify(opts || {})); }
              loadOBJString(name, objSource, opts) { return __canvas3d_loadOBJString(this.id, name, objSource, JSON.stringify(opts || {})); }
              getObjectChildren(name) { return JSON.parse(__canvas3d_getObjectChildren(this.id, name)); }
              getObjectPosition(name) { return JSON.parse(__canvas3d_getObjectPosition(this.id, name)); }
              cloneObject(sourceName, cloneName) { return __canvas3d_cloneObject(this.id, sourceName, cloneName); }

              onDraw(cb)      { __canvasCallbacks[this.id].onDraw = cb; }
              onUpdate(cb)    { __canvasCallbacks[this.id].onUpdate = cb; }
              onKeyDown(cb)   { __canvasCallbacks[this.id].onKeyDown = cb; }
              onKeyUp(cb)     { __canvasCallbacks[this.id].onKeyUp = cb; }
              onMouseDown(cb) { __canvasCallbacks[this.id].onMouseDown = cb; }
              onMouseUp(cb)   { __canvasCallbacks[this.id].onMouseUp = cb; }
              onMouseMove(cb) { __canvasCallbacks[this.id].onMouseMove = cb; }

              isKeyDown(key)  { return __canvas_isKeyDown(this.id, key); }
              isMouseDown()   { return __canvas_isMouseDown(this.id); }
              mouseX()        { return __canvas_getMouseX(this.id); }
              mouseY()        { return __canvas_getMouseY(this.id); }
              getWidth()      { return __canvas_getWidth(this.id); }
              getHeight()     { return __canvas_getHeight(this.id); }

              start() { __canvas_start(this.id); }
              stop()  { __canvas_stop(this.id); }
            }

            export { Canvas, Canvas3D };
          JS
        end

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
            state.scene_renderer.try(&.initialize_gl)
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
            when ClearCommand        then renderer.clear(cmd.r.to_f32, cmd.g.to_f32, cmd.b.to_f32, cmd.a.to_f32)
            when FillRectCommand     then renderer.fill_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.r, cmd.g, cmd.b, cmd.a)
            when StrokeRectCommand   then renderer.stroke_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
            when FillCircleCommand   then renderer.fill_circle(cmd.x, cmd.y, cmd.radius, cmd.r, cmd.g, cmd.b, cmd.a)
            when StrokeCircleCommand then renderer.stroke_circle(cmd.x, cmd.y, cmd.radius, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
            when DrawLineCommand     then renderer.draw_line(cmd.x1, cmd.y1, cmd.x2, cmd.y2, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
            when FillTriangleCommand then renderer.fill_triangle(cmd.x1, cmd.y1, cmd.x2, cmd.y2, cmd.x3, cmd.y3, cmd.r, cmd.g, cmd.b, cmd.a)
            when FillTextCommand     then state.text_renderer.render(renderer, cmd.text, cmd.x, cmd.y, cmd.r, cmd.g, cmd.b, cmd.a, cmd.size)
            end
          end

          state.text_renderer.tick
          renderer.end_frame
        end

        private def self.render_3d_frame(state : State, gl_area : Gtk::GLArea) : Nil
          sr = state.scene_renderer
          scene = state.scene
          cam = state.camera
          return unless sr && scene && cam

          scale = gl_area.scale_factor
          w = gl_area.allocated_width
          h = gl_area.allocated_height

          sr.render(scene, cam, w * scale, h * scale)

          unless state.draw_commands.empty?
            flat = state.flat_renderer
            if flat.initialized?
              LibGL.glDisable(LibGL::GL_DEPTH_TEST)
              flat.begin_frame(w * scale, h * scale, w, h)
              state.draw_commands.each do |cmd|
                case cmd
                when FillRectCommand   then flat.fill_rect(cmd.x, cmd.y, cmd.w, cmd.h, cmd.r, cmd.g, cmd.b, cmd.a)
                when FillTextCommand   then state.text_renderer.render(flat, cmd.text, cmd.x, cmd.y, cmd.r, cmd.g, cmd.b, cmd.a, cmd.size)
                when FillCircleCommand then flat.fill_circle(cmd.x, cmd.y, cmd.radius, cmd.r, cmd.g, cmd.b, cmd.a)
                when DrawLineCommand   then flat.draw_line(cmd.x1, cmd.y1, cmd.x2, cmd.y2, cmd.r, cmd.g, cmd.b, cmd.a, cmd.line_width)
                end
              end
              state.text_renderer.tick
              flat.end_frame
            end
          end
        end

        private def self.attach_input_controllers(id : String, gl_area : Gtk::GLArea) : Nil
          key_controller = Gtk::EventControllerKey.new

          key_controller.key_pressed_signal.connect do |key_val, _, _|
            canvas = State.get(id)

            key_name = Gdk.keyval_name(key_val) || key_val.to_s
            if key_name.size == 1
              key_name = key_name.upcase
            elsif key_name.size > 1
              key_name = key_name[0].upcase.to_s + key_name[1..]
            end

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
            if key_name.size == 1
              key_name = key_name.upcase
            elsif key_name.size > 1
              key_name = key_name[0].upcase.to_s + key_name[1..]
            end

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
        end
      end
    end
  end
end
