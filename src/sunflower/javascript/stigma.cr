module Sunflower
  module JavaScript
    module Stigma
      Log = ::Log.for(self)

      def self.install(sandbox, engine) : Nil
        Log.debug { "Registering runtime bindings" }

        sandbox.bind("__create_widget", 3) do |args|
          Stigma.create(
            parent_id: args[0].as_s,
            kind: args[1].as_s,
            properties_json: args[2].as_s
          )
        end

        sandbox.bind("__destroy_widget", 1) do |args|
          Stigma.destroy(args[0].as_s)
          nil
        end

        sandbox.bind("__unregister_widget", 1) do |args|
          Registry.instance.unregister(args[0].as_s)
          nil
        end

        Log.debug { "Loading minimal runtime" }
        sandbox.eval_mutex! <<-JS
          (function() {
            var readyCallbacks = [];
            var exitCallbacks = [];
            var isReady = false;

            globalThis.Runtime = {
              windows: {},

              onReady: function(cb) {
                isReady ? cb() : readyCallbacks.push(cb);
              },

              onExit: function(cb) {
                exitCallbacks.push(cb);
              },

              flushReady: function() {
                isReady = true;
                for (let i = 0; i < readyCallbacks.length; i++) {
                  readyCallbacks[i]();
                }
                readyCallbacks = [];
              },

              flushExit: function() {
                for (let i = 0; i < exitCallbacks.length; i++) {
                  exitCallbacks[i]();
                }
              },

              getWindow: function(id) {
                return this.windows[id] || null;
              },

              getComponentById: function(id, windowId) {
                if (windowId) {
                  let window = this.windows[windowId];
                  return window && window.components[id] || null;
                }
                return this.findComponentById(id);
              },

              findComponentById: function(id) {
                for (let key in this.windows) {
                  let component = this.windows[key].components[id];
                  if (component) return component;
                }
                return null;
              },

              dispatch: function(componentId, eventName, eventData) {
                let component = Runtime.findComponentById(componentId);
                if (!component || !component.on) return;
                let handler = component.on[eventName];

                if (typeof handler === 'function') {
                  handler.call(component, eventData);
                }
              },

              get componentIds() {
                let ids = [];
                for (let key in this.windows) {
                  let components = this.windows[key].components;
                  if (components) ids = ids.concat(Object.keys(components));
                }
                return ids;
              }
            };
          })();
        JS

        install_module
      end

      private def self.install_module : Nil
        ModuleLoader.register("stigma", <<-JS)
          // Private State
          var _hookStates = {};
          var _hookIndex = 0;
          var _currentFiber = null;

          var _effectStates = {};
          var _pendingEffects = [];

          var _fibers = {};
          var _nextFiberId = 1;

          var _rootVNodes = {};

          var _rerenderQueue = {};
          var _rerenderScheduled = false;

          // Scheduler
          function _scheduleRerender(fiberId) {
            _rerenderQueue[fiberId] = true;

            if (!_rerenderScheduled) {
              _rerenderScheduled = true;
              Promise.resolve().then(function() {
                _rerenderScheduled = false;
                var queue = _rerenderQueue;
                _rerenderQueue = {};

                for (var id in queue) {
                  var fiber = _fibers[id];
                  if (fiber) _rerenderFiber(fiber);
                }
              });
            }
          }

          function _rerenderFiber(fiber) {
            var oldTree = fiber.vnode;
            var newTree = _renderComponent(fiber);
            var result = _reconcileNode(fiber.parentWidgetId, oldTree, newTree);

            fiber.vnode = result;
            if (result) fiber.widgetId = result._widgetId;

            _flushEffects();
          }

          function _renderComponent(fiber) {
            _currentFiber = fiber;
            _hookIndex = 0;
            var result = fiber.component(fiber.properties);
            _currentFiber = null;
            return result;
          }

          function _flushEffects() {
            var effects = _pendingEffects.slice();
            _pendingEffects = [];
            for (var i = 0; i < effects.length; i++) {
              effects[i]();
            }
          }

          // Reconciler
          function _reconcileNode(parentWidgetId, oldNode, newNode) {
            if (!oldNode && !newNode) return null;

            if (!oldNode && newNode) {
              _createNode(parentWidgetId, newNode);
              return newNode;
            }

            if (oldNode && !newNode) {
              _destroyNode(oldNode);
              return null;
            }

            var oldIsText = _isText(oldNode);
            var newIsText = _isText(newNode);

            if (oldIsText && newIsText) return newNode;

            if (oldIsText !== newIsText) {
              _destroyNode(oldNode);
              _createNode(parentWidgetId, newNode);
              return newNode;
            }

            var oldType = oldNode.type;
            var newType = newNode.type;

            if (typeof newType === "function") {
              if (oldType === newType && oldNode._fiberId) {
                var fiber = _fibers[oldNode._fiberId];
                if (fiber) {
                  newNode._fiberId = oldNode._fiberId;
                  fiber.properties = _buildComponentProps(newNode);

                  var oldRendered = fiber.vnode;
                  var newRendered = _renderComponent(fiber);
                  var resultRendered = _reconcileNode(fiber.parentWidgetId, oldRendered, newRendered);

                  fiber.vnode = resultRendered;
                  if (resultRendered) {
                    newNode._widgetId = resultRendered._widgetId;
                    fiber.widgetId = resultRendered._widgetId;
                  }

                  _flushEffects();
                  return newNode;
                }
              }

              _destroyNode(oldNode);
              _createNode(parentWidgetId, newNode);
              return newNode;
            }

            if (typeof newType === "string") {
              if (oldType !== newType) {
                _destroyNode(oldNode);
                _createNode(parentWidgetId, newNode);
                return newNode;
              }

              newNode._widgetId = oldNode._widgetId;
              var widgetId = oldNode._widgetId;

              _applyProps(widgetId, newType, newNode.properties);
              _applyEventHandlers(widgetId, newNode.properties);

              var oldText = _getTextContent(oldNode);
              var newText = _getTextContent(newNode);

              if (oldText !== newText) {
                var comp = Runtime.getComponentById(widgetId);
                if (comp) {
                  if (comp.kind === "LABEL" && comp.setText) comp.setText(newText);
                  else if (comp.kind === "BUTTON" && comp.setText) comp.setText(newText);
                }
              }

              _reconcileChildrenArray(widgetId, oldNode.children, newNode.children);
              return newNode;
            }

            _destroyNode(oldNode);
            _createNode(parentWidgetId, newNode);
            return newNode;
          }

          function _reconcileChildrenArray(parentWidgetId, oldChildren, newChildren) {
            oldChildren = oldChildren || [];
            newChildren = newChildren || [];

            var oldFiltered = _filterChildren(oldChildren);
            var newFiltered = _filterChildren(newChildren);
            var maxLen = Math.max(oldFiltered.length, newFiltered.length);

            for (var i = 0; i < maxLen; i++) {
              var oldChild = i < oldFiltered.length ? oldFiltered[i] : null;
              var newChild = i < newFiltered.length ? newFiltered[i] : null;
              var result = _reconcileNode(parentWidgetId, oldChild, newChild);
              if (i < newFiltered.length) newFiltered[i] = result;
            }
          }

          function _filterChildren(children) {
            var result = [];
            for (var i = 0; i < children.length; i++) {
              var c = children[i];
              if (c !== null && c !== undefined && c !== false) result.push(c);
            }
            return result;
          }

          // Create / Destroy

          function _createNode(parentWidgetId, vnode) {
            if (vnode === null || vnode === undefined || vnode === false) return null;

            if (_isText(vnode)) {
              __create_widget(parentWidgetId, "Label", JSON.stringify({ text: String(vnode) }));
              return null;
            }

            if (typeof vnode.type === "function") {
              var fiberId = "fiber_" + (_nextFiberId++);
              var fiber = {
                id: fiberId,
                component: vnode.type,
                properties: _buildComponentProps(vnode),
                vnode: null,
                widgetId: null,
                parentWidgetId: parentWidgetId
              };

              _fibers[fiberId] = fiber;
              vnode._fiberId = fiberId;

              var rendered = _renderComponent(fiber);
              fiber.vnode = rendered;

              if (rendered) {
                _createNode(parentWidgetId, rendered);
                if (rendered._widgetId) {
                  vnode._widgetId = rendered._widgetId;
                  fiber.widgetId = rendered._widgetId;
                }
              }

              _flushEffects();
              return vnode._widgetId;
            }

            var propertiesForCreate = _buildCreateProps(vnode);
            var widgetId = __create_widget(parentWidgetId, vnode.type, JSON.stringify(propertiesForCreate));
            vnode._widgetId = widgetId;

            _applyEventHandlers(widgetId, vnode.properties);

            var textContent = _getTextContent(vnode);
            if (textContent) {
              var comp = Runtime.getComponentById(widgetId);
              if (comp) {
                if (comp.kind === "LABEL" && comp.setText) comp.setText(textContent);
                else if (comp.kind === "BUTTON" && comp.setText) comp.setText(textContent);
                else if (comp.kind === "ENTRY" && comp.setText) comp.setText(textContent);
              }
            }

            for (var i = 0; i < vnode.children.length; i++) {
              var child = vnode.children[i];
              if (child !== null && child !== undefined && child !== false) {
                if (typeof child === "object") _createNode(widgetId, child);
              }
            }

            return widgetId;
          }

          function _destroyNode(vnode) {
            if (!vnode || _isText(vnode)) return;

            if (vnode._fiberId) {
              var fiber = _fibers[vnode._fiberId];
              if (fiber) {
                if (fiber.vnode) _destroyNode(fiber.vnode);
                _cleanupFiber(fiber);
              }
              return;
            }

            if (vnode.children) {
              for (var i = 0; i < vnode.children.length; i++) {
                _cleanupNode(vnode.children[i]);
              }
            }

            if (vnode._widgetId) {
              try { __destroy_widget(vnode._widgetId); } catch (e) {}
              vnode._widgetId = null;
            }
          }

          function _cleanupNode(vnode) {
            if (!vnode || _isText(vnode)) return;

            if (vnode._fiberId) {
              var fiber = _fibers[vnode._fiberId];
              if (fiber) {
                if (fiber.vnode) _cleanupNode(fiber.vnode);
                _cleanupFiber(fiber);
              }
              return;
            }

            if (vnode.children) {
              for (var i = 0; i < vnode.children.length; i++) {
                _cleanupNode(vnode.children[i]);
              }
            }

            if (vnode._widgetId) {
              try { __unregister_widget(vnode._widgetId); } catch (e) {}
              vnode._widgetId = null;
            }
          }

          function _cleanupFiber(fiber) {
            var effects = _effectStates[fiber.id];
            if (effects) {
              for (var i = 0; i < effects.length; i++) {
                if (effects[i] && typeof effects[i].cleanup === "function") {
                  effects[i].cleanup();
                }
              }
              delete _effectStates[fiber.id];
            }
            delete _hookStates[fiber.id];
            delete _fibers[fiber.id];
          }

          // Helpers
          function _isText(node) {
            return typeof node === "string" || typeof node === "number";
          }

          function _getTextContent(vnode) {
            if (!vnode || !vnode.children) return "";
            return vnode.children
              .filter(function(c) { return _isText(c); })
              .join("");
          }

          function _buildComponentProps(vnode) {
            var properties = {};
            for (var key in vnode.properties) properties[key] = vnode.properties[key];
            if (vnode.children && vnode.children.length > 0) properties.children = vnode.children;
            return properties;
          }

          function _buildCreateProps(vnode) {
            var properties = {};
            for (var key in vnode.properties) {
              if (typeof vnode.properties[key] !== "function") properties[key] = vnode.properties[key];
            }
            return properties;
          }

          function _applyProps(widgetId, type, properties) {
            var comp = Runtime.getComponentById(widgetId);
            if (!comp) return;

            for (var key in properties) {
              var val = properties[key];
              if (typeof val === "function") continue;

              if (key === "className" && comp.removeCssClass && comp.addCssClass) {
                var oldClasses = comp._currentClasses || [];
                for (var ci = 0; ci < oldClasses.length; ci++) comp.removeCssClass(oldClasses[ci]);
                var newClasses = val ? val.split(" ").filter(function(c) { return c; }) : [];
                for (var ci = 0; ci < newClasses.length; ci++) comp.addCssClass(newClasses[ci]);
                comp._currentClasses = newClasses;
              } else if (key === "visible" && comp.setVisible) {
                comp.setVisible(val);
              }
            }
          }

          function _applyEventHandlers(widgetId, properties) {
            var comp = Runtime.getComponentById(widgetId);
            if (!comp) return;

            var eventMap = {
              onPress: "press",
              onClick: "press",
              onChange: "change",
              onRelease: "release",
              onKeyPress: "keyPress",
              onFocusChange: "focusChange"
            };

            for (var key in properties) {
              if (typeof properties[key] !== "function") continue;
              var eventName = eventMap[key];
              if (eventName) comp.on[eventName] = properties[key];
            }

            if (properties.className) {
              comp._currentClasses = properties.className.split(" ").filter(function(c) { return c; });
            }
          }

          // Public Exports
          export function createElement(type, properties) {
            var children = [];
            for (var i = 2; i < arguments.length; i++) {
              var child = arguments[i];
              if (Array.isArray(child)) {
                children = children.concat(child);
              } else if (child !== null && child !== undefined && child !== false) {
                children.push(child);
              }
            }
            return {
              type: type,
              properties: properties || {},
              children: children,
              _key: properties && properties.key ? properties.key : null,
              _widgetId: null,
              _fiberId: null
            };
          }

          export var Fragment = function(properties) {
            return createElement("Box", { orientation: "vertical" }, properties.children);
          };

          export function useState(initial) {
            var fiber = _currentFiber;
            var index = _hookIndex++;

            if (!_hookStates[fiber.id]) {
              _hookStates[fiber.id] = [];
            }

            var states = _hookStates[fiber.id];
            if (index >= states.length) {
              states.push(typeof initial === "function" ? initial() : initial);
            }

            var capturedIndex = index;
            var capturedFiberId = fiber.id;

            var setter = function(value) {
              var old = _hookStates[capturedFiberId][capturedIndex];
              var next = typeof value === "function" ? value(old) : value;
              if (old !== next) {
                _hookStates[capturedFiberId][capturedIndex] = next;
                _scheduleRerender(capturedFiberId);
              }
            };

            return [states[index], setter];
          }

          export function useEffect(callback, deps) {
            var fiber = _currentFiber;
            var index = _hookIndex++;

            if (!_effectStates[fiber.id]) {
              _effectStates[fiber.id] = [];
            }

            var effects = _effectStates[fiber.id];
            var prev = effects[index];
            var shouldRun = true;

            if (prev && deps !== undefined) {
              shouldRun = !deps.every(function(dep, i) {
                return dep === prev.deps[i];
              });
            }

            if (shouldRun) {
              if (prev && typeof prev.cleanup === "function") {
                prev.cleanup();
              }
              var capturedFiberId = fiber.id;
              var capturedIndex = index;
              _pendingEffects.push(function() {
                var cleanup = callback();
                _effectStates[capturedFiberId][capturedIndex] = {
                  deps: deps,
                  cleanup: typeof cleanup === "function" ? cleanup : null
                };
              });
            } else {
              effects[index] = prev;
            }
          }

          export function render(containerId, component, properties) {
            var vnode;
            if (typeof component === "function") {
              vnode = createElement(component, properties || {});
            } else {
              vnode = component;
            }

            var oldVNode = _rootVNodes[containerId];

            if (oldVNode) {
              var result = _reconcileNode(containerId, oldVNode, vnode);
              _rootVNodes[containerId] = result;
            } else {
              _rootVNodes[containerId] = vnode;
              _createNode(containerId, vnode);
            }

            _flushEffects();
          }

          class Window {
            static get instance() {
              return Runtime.windows["Main"] || null;
            }

            static get isFullscreen() {
              var window = this.instance;
              return window ? window.isFullscreen : false;
            }

            static fullscreen() {
              var window = this.instance;
              if (window) window.fullscreen();
            }

            static unfullscreen() {
              var window = this.instance;
              if (window) window.unfullscreen();
            }

            static toggleFullscreen() {
              if (this.isFullscreen) {
                this.unfullscreen();
              } else {
                this.fullscreen();
              }
            }

            static maximize() {
              var window = this.instance;
              if (window) window.maximize();
            }

            static minimize() {
              var window = this.instance;
              if (window) window.minimize();
            }

            static close() {
              var window = this.instance;
              if (window) window.close();
            }

            static setTitle(title) {
              var window = this.instance;
              if (window) window.setTitle(title);
            }
          }

          export { Window };

          export default {
            createElement: createElement,
            Fragment: Fragment,
            useState: useState,
            useEffect: useEffect,
            render: render,
            onReady: function(cb) { Runtime.onReady(cb); },
            onExit: function(cb) { Runtime.onExit(cb); },
            getComponentById: function(id) { return Runtime.getComponentById(id); },
            findComponentById: function(id) { return Runtime.findComponentById(id); }
          };
        JS
      end

      def self.create(parent_id : String, kind : String, properties_json : String) : String
        properties = JSON.parse(properties_json)
        id = properties["id"]?.try(&.as_s) || Random::Secure.hex(8)
        class_name = properties["className"]?.try(&.as_s) || ""

        parent_component = Registry.instance.registered_components[parent_id]?
        unless parent_component
          Log.error { "Parent #{parent_id} not found" }
          return id
        end

        window_id = parent_component.window_id

        widget = build_widget(kind, id, properties)
        widget.name = id

        apply_common_properties(widget, properties)
        apply_css_class(widget, class_name)
        connect_signals(widget, id)
        append_to_parent(widget, parent_component.widget)

        component = Component.new(
          id: id,
          class_name: class_name,
          kind: kind,
          widget: widget,
          window_id: window_id
        )
        Registry.instance.register(component)

        id
      end

      def self.destroy(widget_id : String) : Nil
        component = Registry.instance.registered_components[widget_id]?
        return unless component

        if component.kind == "Canvas"
          JavaScript::Engine.instance.scene_view.destroy_widget(widget_id)
        end

        component.widget.unparent if component.widget.parent
        Registry.instance.unregister(widget_id)
      end

      private def self.build_widget(kind : String, id : String, properties : JSON::Any) : Gtk::Widget
        case kind
        when "Box"                 then build_box(properties)
        when "Label"               then build_label(properties)
        when "Button"              then build_button(properties)
        when "Entry"               then build_entry(properties)
        when "Image"               then Gtk::Picture.new
        when "ScrolledWindow"      then build_scrolled_window(properties)
        when "HorizontalSeparator" then Gtk::Separator.new(orientation: Gtk::Orientation::Horizontal)
        when "VerticalSeparator"   then Gtk::Separator.new(orientation: Gtk::Orientation::Vertical)
        when "Switch"              then Gtk::Switch.new
        when "Canvas"              then JavaScript::Engine.instance.scene_view.create_widget(id, properties)
        else
          Log.warn { "Unknown widget type '#{kind}', creating Box" }
          Gtk::Box.new(orientation: Gtk::Orientation::Vertical)
        end
      end

      private def self.build_box(properties : JSON::Any) : Gtk::Box
        orientation = properties["orientation"]?.try(&.as_s) == "horizontal" ? Gtk::Orientation::Horizontal : Gtk::Orientation::Vertical

        spacing = prop_int(properties, "spacing") || 0
        homogeneous = prop_bool(properties, "homogeneous")

        Gtk::Box.new(orientation: orientation, spacing: spacing, homogeneous: homogeneous)
      end

      private def self.build_label(properties : JSON::Any) : Gtk::Label
        label = Gtk::Label.new(str: properties["text"]?.try(&.as_s) || "")
        label.wrap = prop_bool(properties, "wrap")
        label.wrap_mode = Pango::WrapMode::WordChar
        label.hexpand = true
        label.max_width_chars = 1
        label
      end

      private def self.build_button(properties : JSON::Any) : Gtk::Button
        Gtk::Button.new_with_label(properties["text"]?.try(&.as_s) || "")
      end

      private def self.build_entry(properties : JSON::Any) : Gtk::Entry
        entry = Gtk::Entry.new
        properties["text"]?.try(&.as_s).try { |t| entry.text = t }
        properties["placeHolder"]?.try(&.as_s).try { |p| entry.placeholder_text = p }
        entry.visibility = false if properties["inputType"]?.try(&.as_s) == "password"
        entry
      end

      private def self.build_scrolled_window(properties : JSON::Any) : Gtk::ScrolledWindow
        sw = Gtk::ScrolledWindow.new
        sw.hscrollbar_policy = Gtk::PolicyType::Never
        sw.vscrollbar_policy = Gtk::PolicyType::Automatic
        sw.propagate_natural_width = false
        sw.propagate_natural_height = false

        if prop_bool(properties, "expand")
          sw.vexpand = true
          sw.hexpand = true
        end

        sw
      end

      private def self.apply_common_properties(widget : Gtk::Widget, properties : JSON::Any) : Nil
        if prop_bool(properties, "expand")
          widget.vexpand = true
          widget.hexpand = true
        end

        properties["horizontalAlignment"]?.try(&.as_s).try do |align|
          widget.halign = parse_alignment(align)
        end

        properties["verticalAlignment"]?.try(&.as_s).try do |align|
          widget.valign = parse_alignment(align)
        end
      end

      private def self.apply_css_class(widget : Gtk::Widget, class_name : String) : Nil
        widget.add_css_class(class_name) unless class_name.empty?
      end

      private def self.parse_alignment(value : String) : Gtk::Align
        case value.downcase
        when "center" then Gtk::Align::Center
        when "start"  then Gtk::Align::Start
        when "end"    then Gtk::Align::End
        else               Gtk::Align::Fill
        end
      end

      private def self.connect_signals(widget : Gtk::Widget, id : String) : Nil
        case widget
        when Gtk::Button
          widget.clicked_signal.connect do
            Registry.instance.registered_components[id]?.try(&.dispatch_event("press"))
          end
        when Gtk::Entry
          widget.buffer.inserted_text_signal.connect do
            Registry.instance.registered_components[id]?.try(&.dispatch_event("change", "\"#{widget.text}\""))
          end
          widget.buffer.deleted_text_signal.connect do
            Registry.instance.registered_components[id]?.try(&.dispatch_event("change", "\"#{widget.text}\""))
          end
        when Gtk::Switch
          widget.notify_signal["active"].connect do
            Registry.instance.registered_components[id]?.try(&.dispatch_event("change", widget.active?.to_s))
          end
        end
      end

      private def self.append_to_parent(widget : Gtk::Widget, parent : Gtk::Widget) : Nil
        case parent
        when Gtk::Box            then parent.append(widget)
        when Gtk::ScrolledWindow then parent.child = widget
        when Gtk::ListBox        then parent.append(widget)
        else
          Log.warn { "Cannot append to #{parent.class}" }
        end
      end

      # Handles the common pattern where a bool prop might be
      # an actual bool OR the string "true"/"false".
      private def self.prop_bool(properties : JSON::Any, key : String) : Bool
        properties[key]?.try(&.as_bool?) || properties[key]?.try(&.as_s) == "true" || false
      end

      # Handles int properties that might be strings.
      private def self.prop_int(properties : JSON::Any, key : String) : Int32?
        properties[key]?.try(&.as_i?) || properties[key]?.try(&.as_s.to_i?)
      end
    end
  end
end
