module Sunflower
  class Component
    Log = ::Log.for(self)

    getter id : String
    getter class_name : String
    getter kind : String
    getter widget : Gtk::Widget
    getter window_id : String

    private getter engine : JavaScript::Engine = JavaScript::Engine.instance

    def initialize(@id : String, @class_name : String, @kind : String, @widget : Gtk::Widget, @window_id : String)
      register_js_object
    end

    # The full JS path: $.windows["windowId"].components["id"]
    def path : String
      "$.windows[\"#{window_id}\"].components[\"#{id}\"]"
    end

    # Called from Crystal to dispatch a GTK event to JS handlers.
    # Uses the __dispatch function which looks up `component.on[eventName]`
    # and calls it directly — no string eval of user code.
    def dispatch_event(event_name : String, event_data : String? = nil) : Nil
      source_code = if event_data
                      "__dispatch(\"#{id}\", \"#{event_name}\", #{event_data})"
                    else
                      "__dispatch(\"#{id}\", \"#{event_name}\")"
                    end

      engine.sandbox.eval_mutex!(source_code)
    rescue ex : Medusa::Exceptions::InternalException
      Log.error(exception: ex) { "Event #{event_name} on #{id}: #{ex.message}" }
    end

    # -------------------------------------------------------------------------
    # JS Object Registration
    #
    # Creates a component at $.windows[windowId].components[id]:
    # {
    #   isMounted: true,
    #   id: "...",
    #   className: "...",
    #   kind: "BUTTON",
    #   on: {},           ← event handlers (user-assigned JS functions)
    #   state: <lazy>,    ← Object.defineProperty getter, reads from Crystal on access
    #   setText(), ...    ← bound Crystal methods
    # }
    # -------------------------------------------------------------------------

    private def register_js_object : Nil
      sandbox = engine.sandbox

      # Create the base object with `on` for event handlers
      sandbox.eval_mutex!(
        "#{path} = {\n" \
        "  isMounted: true,\n" \
        "  id: \"#{id}\",\n" \
        "  windowId: \"#{window_id}\",\n" \
        "  className: \"#{class_name}\",\n" \
        "  kind: \"#{kind.upcase}\",\n" \
        "  on: {}\n" \
        "};\n"
      )

      # Install lazy state getter — state is fetched from Crystal on demand
      sandbox.eval_mutex!("__installStateGetter(#{path});")

      # Register widget-specific methods (setText, append, etc.)
      sandbox.eval_mutex!("__installMethods(#{path});")
    end
  end
end
