(function() {
  // Virtual DOM node constructor
  globalThis.h = function(type, props) {
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
  };

  // State Management

  var _hookStates = {};
  var _hookIndex = 0;
  var _currentFiber = null;

  globalThis.useState = function(initial) {
    var fiber = _currentFiber;
    var index = _hookIndex++;

    if (!_hookStates[fiber.id]) {
      _hookStates[fiber.id] = [];
    }

    var states = _hookStates[fiber.id];
    if (index >= states.length) {
      states.push(typeof initial === 'function' ? initial() : initial);
    }

    var capturedIndex = index;
    var capturedFiberId = fiber.id;

    var setter = function(value) {
      var old = _hookStates[capturedFiberId][capturedIndex];
      var next = typeof value === 'function' ? value(old) : value;
      if (old !== next) {
        _hookStates[capturedFiberId][capturedIndex] = next;
        _scheduleRerender(capturedFiberId);
      }
    };

    return [states[index], setter];
  };

  // Effect Hook

  var _effectStates = {};

  globalThis.useEffect = function(callback, deps) {
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
      if (prev && typeof prev.cleanup === 'function') {
        prev.cleanup();
      }
      var capturedFiberId = fiber.id;
      var capturedIndex = index;
      _pendingEffects.push(function() {
        var cleanup = callback();
        _effectStates[capturedFiberId][capturedIndex] = {
          deps: deps,
          cleanup: typeof cleanup === 'function' ? cleanup : null
        };
      });
    } else {
      effects[index] = prev;
    }
  };

  var _pendingEffects = [];

  function _flushEffects() {
    var effects = _pendingEffects.slice();
    _pendingEffects = [];
    for (var i = 0; i < effects.length; i++) {
      effects[i]();
    }
  }

  // Rerender Scheduling

  var _rerenderQueue = {};
  var _rerenderScheduled = false;

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
          if (fiber) {
            _rerenderFiber(fiber);
          }
        }
      });
    }
  }

  // Re-render: diff old vnode tree against new one IN-PLACE

  function _rerenderFiber(fiber) {
    var oldTree = fiber.vnode;
    var newTree = _renderComponent(fiber);

    var resultNode = _reconcileNode(fiber.parentWidgetId, oldTree, newTree);
    fiber.vnode = resultNode;

    if (resultNode) {
      fiber.widgetId = resultNode._widgetId;
    }

    _flushEffects();
  }

  // Fiber Registry

  var _fibers = {};
  var _nextFiberId = 1;

  // Rendering

  function _renderComponent(fiber) {
    _currentFiber = fiber;
    _hookIndex = 0;
    var result = fiber.component(fiber.props);
    _currentFiber = null;
    return result;
  }

  // Reconciler — the core diffing engine

  function _reconcileNode(parentWidgetId, oldNode, newNode) {
    // Both null
    if (!oldNode && !newNode) return null;

    // New node where there was none — create
    if (!oldNode && newNode) {
      _createNode(parentWidgetId, newNode);
      return newNode;
    }

    // Old node removed — destroy
    if (oldNode && !newNode) {
      _destroyNode(oldNode);
      return null;
    }

    var oldIsText = _isText(oldNode);
    var newIsText = _isText(newNode);

    // Text nodes
    if (oldIsText && newIsText) {
      // Text can't be updated in-place since they're primitives
      // and we created Labels for them — just leave them
      return newNode;
    }

    // Type mismatch between text and element
    if (oldIsText !== newIsText) {
      _destroyNode(oldNode);
      _createNode(parentWidgetId, newNode);
      return newNode;
    }

    // Both are vnodes from here
    var oldType = oldNode.type;
    var newType = newNode.type;

    // Function components
    if (typeof newType === 'function') {
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

      // Different component — destroy and create fresh
      _destroyNode(oldNode);
      _createNode(parentWidgetId, newNode);
      return newNode;
    }

    // Native elements
    if (typeof newType === 'string') {
      if (oldType !== newType) {
        // Different element type — destroy and recreate
        _destroyNode(oldNode);
        _createNode(parentWidgetId, newNode);
        return newNode;
      }

      // ---------------------------------------------------------------
      // SAME element type — UPDATE IN PLACE
      // ---------------------------------------------------------------
      newNode._widgetId = oldNode._widgetId;
      var widgetId = oldNode._widgetId;

      // Update props
      _applyProps(widgetId, newType, newNode.props);
      _applyEventHandlers(widgetId, newNode.props);

      // Update text content (but NOT for Entry — user is typing)
      var oldText = _getTextContent(oldNode);
      var newText = _getTextContent(newNode);

      if (oldText !== newText) {
        var comp = $.getComponentById(widgetId);
        if (comp) {
          if (comp.kind === 'LABEL' && comp.setText) comp.setText(newText);
          else if (comp.kind === 'BUTTON' && comp.setText) comp.setText(newText);
          // Skip ENTRY — don't overwrite user input
        }
      }

      // Reconcile children
      _reconcileChildrenArray(widgetId, oldNode.children, newNode.children);

      return newNode;
    }

    // Fallback
    _destroyNode(oldNode);
    _createNode(parentWidgetId, newNode);
    return newNode;
  }

  // Reconcile arrays of children, filtering out nulls
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

      if (i < newFiltered.length) {
        newFiltered[i] = result;
      }
    }
  }

  function _filterChildren(children) {
    var result = [];
    for (var i = 0; i < children.length; i++) {
      var c = children[i];
      if (c !== null && c !== undefined && c !== false) {
        result.push(c);
      }
    }
    return result;
  }

  // Create — builds new GTK widgets from a vnode tree

  function _createNode(parentWidgetId, vnode) {
    if (vnode === null || vnode === undefined || vnode === false) return null;

    if (typeof vnode === 'string' || typeof vnode === 'number') {
      __create_widget(parentWidgetId, "Label", JSON.stringify({
        text: String(vnode)
      }));
      return null;
    }

    if (typeof vnode.type === 'function') {
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

    // Native element
    var propsForCreate = _buildCreateProps(vnode);
    var widgetId = __create_widget(parentWidgetId, vnode.type, JSON.stringify(propsForCreate));
    vnode._widgetId = widgetId;

    _applyEventHandlers(widgetId, vnode.props);

    // Set text content
    var textContent = _getTextContent(vnode);
    if (textContent) {
      var comp = $.getComponentById(widgetId);
      if (comp) {
        if (comp.kind === 'LABEL' && comp.setText) comp.setText(textContent);
        else if (comp.kind === 'BUTTON' && comp.setText) comp.setText(textContent);
        else if (comp.kind === 'ENTRY' && comp.setText) comp.setText(textContent);
      }
    }

    // Recurse children
    for (var i = 0; i < vnode.children.length; i++) {
      var child = vnode.children[i];
      if (child !== null && child !== undefined && child !== false) {
        if (typeof child === 'object') {
          _createNode(widgetId, child);
        }
      }
    }

    return widgetId;
  }

  // Destroy — removes GTK widgets and cleans up fibers

  function _destroyNode(vnode) {
    if (!vnode || typeof vnode === 'string' || typeof vnode === 'number') return;

    if (vnode._fiberId) {
      var fiber = _fibers[vnode._fiberId];
      if (fiber) {
        if (fiber.vnode) {
          _destroyNode(fiber.vnode);
          fiber.vnode = null;
        }

        var effects = _effectStates[fiber.id];
        if (effects) {
          for (var i = 0; i < effects.length; i++) {
            if (effects[i] && typeof effects[i].cleanup === 'function') {
              effects[i].cleanup();
            }
          }
          delete _effectStates[fiber.id];
        }
        delete _hookStates[fiber.id];
        delete _fibers[vnode._fiberId];
      }
      return;
    }

    if (vnode.children) {
      for (var i = 0; i < vnode.children.length; i++) {
        _destroyNode(vnode.children[i]);
      }
    }

    if (vnode._widgetId) {
      try {
        __destroy_widget(vnode._widgetId);
      } catch(e) {}
      vnode._widgetId = null;
    }
  }

  // Helpers

  function _isText(node) {
    return typeof node === 'string' || typeof node === 'number';
  }

  function _getTextContent(vnode) {
    if (!vnode || !vnode.children) return '';
    return vnode.children
      .filter(function(c) { return typeof c === 'string' || typeof c === 'number'; })
      .join('');
  }

  function _buildComponentProps(vnode) {
    var props = {};
    for (var key in vnode.props) {
      props[key] = vnode.props[key];
    }
    if (vnode.children && vnode.children.length > 0) {
      props.children = vnode.children;
    }
    return props;
  }

  function _buildCreateProps(vnode) {
    var props = {};
    for (var key in vnode.props) {
      var val = vnode.props[key];
      if (typeof val !== 'function') {
        props[key] = val;
      }
    }
    return props;
  }

  function _applyProps(widgetId, type, props) {
    var comp = $.getComponentById(widgetId);
    if (!comp) return;

    for (var key in props) {
      var val = props[key];
      if (typeof val === 'function') continue;

      switch(key) {
        case 'className':
          if (comp.addCssClass) comp.addCssClass(val);
          break;
        case 'visible':
          if (comp.setVisible) comp.setVisible(val);
          break;
      }
    }
  }

  function _applyEventHandlers(widgetId, props) {
    var comp = $.getComponentById(widgetId);
    if (!comp) return;

    for (var key in props) {
      if (typeof props[key] !== 'function') continue;

      if (key === 'onPress') {
        comp.on.press = props[key];
      } else if (key === 'onChange') {
        comp.on.change = props[key];
      } else if (key === 'onClick') {
        comp.on.press = props[key];
      }
    }
  }

  // Public API: $.render()

  var _rootVNodes = {};

  $.render = function(containerId, component, props) {
    var vnode;
    if (typeof component === 'function') {
      vnode = h(component, props || {});
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
  };

  // Fragment support

  globalThis.Fragment = function(props) {
    return h("Box", { orientation: "vertical" }, props.children);
  };

})();