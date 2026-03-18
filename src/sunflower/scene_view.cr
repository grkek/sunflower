module Sunflower
  class SceneView
    Log = ::Log.for(self)

    class State
      property viewport : Tachyon::Viewport
      property engine : Tachyon::Scripting::Engine? = nil
      property fixed_timestep : Float64
      property accumulator : Float64 = 0.0

      def initialize(@viewport, @fixed_timestep = 1.0 / 60.0)
      end

      def update(dt : Float64)
        if engine = @engine
          engine.commands.clear
          engine.call_on_update(dt)

          @accumulator += dt

          while @accumulator >= @fixed_timestep
            engine.call_on_fixed_update(@fixed_timestep)
            @accumulator -= @fixed_timestep
          end

          @viewport.submit_commands(engine.commands)
          @viewport.cursor.try(&.update(engine.input_state))
        end
      end

      def destroy
        @engine.try(&.destroy)
        @engine = nil
        @viewport.destroy
      end
    end

    getter registry : Hash(String, State) = {} of String => State

    def create_widget(id : String, props : JSON::Any) : Gtk::GLArea
      width = (props["width"]?.try(&.as_i?) || props["width"]?.try(&.as_s.to_i?)) || 800
      height = (props["height"]?.try(&.as_i?) || props["height"]?.try(&.as_s.to_i?)) || 600
      fps = (props["framesPerSecond"]?.try(&.as_i?) || props["framesPerSecond"]?.try(&.as_s.to_i?)) || 60

      viewport = Tachyon::Viewport.new(id: id)
      state = State.new(viewport, fixed_timestep: 1.0 / fps)
      @registry[id] = state

      viewport.area.set_size_request(width, height)
      viewport.area.realize_signal.connect { on_realize(id) }

      viewport.area
    end

    def destroy_widget(id : String) : Nil
      if state = @registry.delete(id)
        state.destroy
      end
    end

    private def on_realize(id : String) : Nil
      state = @registry[id]?
      return unless state

      engine = Tachyon::Scripting::Engine.new(
        state.viewport.scene,
        state.viewport.camera,
        state.viewport.light_manager
      )

      engine.canvas = state.viewport.canvas_2d
      engine.audio_engine = state.viewport.audio_engine
      engine.viewport = state.viewport

      state.engine = engine

      context = JavaScript::Engine.instance.sandbox.engine.context
      engine.bind(context)

      if namespace = JavaScript::Engine.instance.last_module_namespace
        engine.adopt_module(namespace)
        engine.call_on_start
      end

      attach_input(state, engine)

      state.viewport.on_before_render do |dt|
        state.update(dt)
      end
    end

    private def attach_input(state : State, engine : Tachyon::Scripting::Engine) : Nil
      viewport = state.viewport
      key_controller = Gtk::EventControllerKey.new

      key_controller.key_pressed_signal.connect do |keyval, _, _|
        key_name = Gdk.keyval_name(keyval)
        engine.input_state.on_key_press(key_name) if key_name
        false
      end

      key_controller.key_released_signal.connect do |keyval, _, _|
        key_name = Gdk.keyval_name(keyval)
        engine.input_state.on_key_release(key_name) if key_name
      end

      viewport.area.add_controller(key_controller)

      motion = Gtk::EventControllerMotion.new

      motion.motion_signal.connect do |x, y|
        engine.input_state.on_mouse_move(x.to_f32, y.to_f32)
      end

      viewport.area.add_controller(motion)

      click = Gtk::GestureClick.new

      click.pressed_signal.connect do |_, x, y|
        engine.input_state.on_mouse_button_press(0)
        viewport.area.grab_focus
      end

      click.released_signal.connect do |_, x, y|
        engine.input_state.on_mouse_button_release(0)
      end

      viewport.area.add_controller(click)
    end
  end
end
