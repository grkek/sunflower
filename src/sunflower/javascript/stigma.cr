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
            props_json: args[2].as_s
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
            globalThis.__runtime = {
              windows: {},

              _readyCallbacks: [],
              _exitCallbacks: [],
              _isReady: false,

              onReady: function(cb) {
                this._isReady ? cb() : this._readyCallbacks.push(cb);
              },

              onExit: function(cb) {
                this._exitCallbacks.push(cb);
              },

              flushReady: function() {
                this._isReady = true;
                for (var i = 0; i < this._readyCallbacks.length; i++) {
                  this._readyCallbacks[i]();
                }
                this._readyCallbacks = [];
              },

              flushExit: function() {
                for (var i = 0; i < this._exitCallbacks.length; i++) {
                  this._exitCallbacks[i]();
                }
              },

              getWindow: function(id) {
                return this.windows[id] || null;
              },

              getComponentById: function(componentId, windowId) {
                if (windowId) {
                  var w = this.windows[windowId];
                  return w ? (w.components[componentId] || null) : null;
                }
                return this.findComponentById(componentId);
              },

              findComponentById: function(componentId) {
                for (var key in this.windows) {
                  var w = this.windows[key];
                  if (w.components && w.components[componentId]) {
                    return w.components[componentId];
                  }
                }
                return null;
              },

              get componentIds() {
                var ids = [];
                for (var key in this.windows) {
                  var w = this.windows[key];
                  if (w.components) ids = ids.concat(Object.keys(w.components));
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
            var result = fiber.component(fiber.props);
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
                  fiber.props = _buildComponentProps(newNode);

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

              _applyProps(widgetId, newType, newNode.props);
              _applyEventHandlers(widgetId, newNode.props);

              var oldText = _getTextContent(oldNode);
              var newText = _getTextContent(newNode);

              if (oldText !== newText) {
                var comp = __runtime.getComponentById(widgetId);
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
                props: _buildComponentProps(vnode),
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

            var propsForCreate = _buildCreateProps(vnode);
            var widgetId = __create_widget(parentWidgetId, vnode.type, JSON.stringify(propsForCreate));
            vnode._widgetId = widgetId;

            _applyEventHandlers(widgetId, vnode.props);

            var textContent = _getTextContent(vnode);
            if (textContent) {
              var comp = __runtime.getComponentById(widgetId);
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
            var props = {};
            for (var key in vnode.props) props[key] = vnode.props[key];
            if (vnode.children && vnode.children.length > 0) props.children = vnode.children;
            return props;
          }

          function _buildCreateProps(vnode) {
            var props = {};
            for (var key in vnode.props) {
              if (typeof vnode.props[key] !== "function") props[key] = vnode.props[key];
            }
            return props;
          }

          function _applyProps(widgetId, type, props) {
            var comp = __runtime.getComponentById(widgetId);
            if (!comp) return;

            for (var key in props) {
              var val = props[key];
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

          function _applyEventHandlers(widgetId, props) {
            var comp = __runtime.getComponentById(widgetId);
            if (!comp) return;

            var eventMap = {
              onPress: "press",
              onClick: "press",
              onChange: "change",
              onRelease: "release",
              onKeyPress: "keyPress",
              onFocusChange: "focusChange"
            };

            for (var key in props) {
              if (typeof props[key] !== "function") continue;
              var eventName = eventMap[key];
              if (eventName) comp.on[eventName] = props[key];
            }

            if (props.className) {
              comp._currentClasses = props.className.split(" ").filter(function(c) { return c; });
            }
          }

          // Public Exports
          export function createElement(type, props) {
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
              props: props || {},
              children: children,
              _key: props && props.key ? props.key : null,
              _widgetId: null,
              _fiberId: null
            };
          }

          export var Fragment = function(props) {
            return createElement("Box", { orientation: "vertical" }, props.children);
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

          export function render(containerId, component, props) {
            var vnode;
            if (typeof component === "function") {
              vnode = createElement(component, props || {});
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

          export function onReady(cb) { __runtime.onReady(cb); }
          export function onExit(cb) { __runtime.onExit(cb); }
          export function getWindow(id) { return __runtime.getWindow(id); }
          export function getComponentById(id, wid) { return __runtime.getComponentById(id, wid); }
          export function findComponentById(id) { return __runtime.findComponentById(id); }

          export default {
            createElement: createElement,
            Fragment: Fragment,
            useState: useState,
            useEffect: useEffect,
            render: render,
            onReady: onReady,
            onExit: onExit,
            getWindow: getWindow,
            getComponentById: getComponentById,
            findComponentById: findComponentById,
            get windows() { return __runtime.windows; },
            get mainWindow() { return __runtime.windows["Main"] || null; },
            get windowIds() { return Object.keys(__runtime.windows); },
            get componentIds() { return __runtime.componentIds; }
          };
        JS
      end

      def self.create(parent_id : String, kind : String, props_json : String) : String
        props = JSON.parse(props_json)
        id = props["id"]?.try(&.as_s) || Random::Secure.hex(8)
        class_name = props["className"]?.try(&.as_s) || ""

        parent_component = Registry.instance.registered_components[parent_id]?
        unless parent_component
          Log.error { "Parent #{parent_id} not found" }
          return id
        end

        window_id = parent_component.window_id

        widget = build_widget(kind, id, props)
        widget.name = id

        apply_common_properties(widget, props)
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

        component.widget.unparent if component.widget.parent
        Registry.instance.unregister(widget_id)
        Log.debug { "Destroyed #{widget_id}" }
      end

      private def self.build_widget(kind : String, id : String, props : JSON::Any) : Gtk::Widget
        case kind
        when "Box"              then build_box(props)
        when "Label"            then build_label(props)
        when "Button"           then build_button(props)
        when "Entry"            then build_entry(props)
        when "Image"            then Gtk::Picture.new
        when "ScrolledWindow"   then build_scrolled_window(props)
        when "HorizontalSeparator" then Gtk::Separator.new(orientation: Gtk::Orientation::Horizontal)
        when "VerticalSeparator"   then Gtk::Separator.new(orientation: Gtk::Orientation::Vertical)
        when "Switch"           then Gtk::Switch.new
        when "Canvas"           then StandardLibrary::Canvas.create_widget(id, props)
        else
          Log.warn { "Unknown widget type '#{kind}', creating Box" }
          Gtk::Box.new(orientation: Gtk::Orientation::Vertical)
        end
      end

      private def self.build_box(props : JSON::Any) : Gtk::Box
        orientation = props["orientation"]?.try(&.as_s) == "horizontal" \
          ? Gtk::Orientation::Horizontal
          : Gtk::Orientation::Vertical

        spacing = prop_int(props, "spacing") || 0
        homogeneous = prop_bool(props, "homogeneous")

        Gtk::Box.new(orientation: orientation, spacing: spacing, homogeneous: homogeneous)
      end

      private def self.build_label(props : JSON::Any) : Gtk::Label
        label = Gtk::Label.new(str: props["text"]?.try(&.as_s) || "")
        label.wrap = prop_bool(props, "wrap")
        label.wrap_mode = Pango::WrapMode::WordChar
        label.hexpand = true
        label.max_width_chars = 1
        label
      end

      private def self.build_button(props : JSON::Any) : Gtk::Button
        Gtk::Button.new_with_label(props["text"]?.try(&.as_s) || "")
      end

      private def self.build_entry(props : JSON::Any) : Gtk::Entry
        entry = Gtk::Entry.new
        props["text"]?.try(&.as_s).try { |t| entry.text = t }
        props["placeHolder"]?.try(&.as_s).try { |p| entry.placeholder_text = p }
        entry.visibility = false if props["inputType"]?.try(&.as_s) == "password"
        entry
      end

      private def self.build_scrolled_window(props : JSON::Any) : Gtk::ScrolledWindow
        sw = Gtk::ScrolledWindow.new
        sw.hscrollbar_policy = Gtk::PolicyType::Never
        sw.vscrollbar_policy = Gtk::PolicyType::Automatic
        sw.propagate_natural_width = false
        sw.propagate_natural_height = false

        if prop_bool(props, "expand")
          sw.vexpand = true
          sw.hexpand = true
        end

        sw
      end

      private def self.apply_common_properties(widget : Gtk::Widget, props : JSON::Any) : Nil
        if prop_bool(props, "expand")
          widget.vexpand = true
          widget.hexpand = true
        end

        props["horizontalAlignment"]?.try(&.as_s).try do |align|
          widget.halign = parse_alignment(align)
        end

        props["verticalAlignment"]?.try(&.as_s).try do |align|
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
      private def self.prop_bool(props : JSON::Any, key : String) : Bool
        props[key]?.try(&.as_bool?) || props[key]?.try(&.as_s) == "true" || false
      end

      # Handles int props that might be strings.
      private def self.prop_int(props : JSON::Any, key : String) : Int32?
        props[key]?.try(&.as_i?) || props[key]?.try(&.as_s.to_i?)
      end
    end
  end
end
