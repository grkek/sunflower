module Sunflower
  module JavaScript
    module XML
      class Transpiler
        Log = ::Log.for(self)

        @source : String
        @pos : Int32 = 0
        @output : IO::Memory

        def self.transform(source : String) : String
          new(source).transform
        end

        def initialize(@source : String)
          @output = IO::Memory.new
        end

        def transform : String
          while @pos < @source.size
            if looking_at_jsx?
              transpile_jsx
            else
              @output << current
              advance
            end
          end

          @output.to_s
        end

        # Detect if we're at a JSX opening tag.
        # Must be `<` followed by an uppercase letter (component name).
        # This avoids matching `<` in comparisons like `a < b`.
        private def looking_at_jsx? : Bool
          return false unless current == '<'
          return false if @pos + 1 >= @source.size

          next_char = @source[@pos + 1]

          # <Uppercase = JSX element
          # </Uppercase = JSX closing tag (handled inside transpile_jsx)
          next_char.uppercase?
        end

        private def transpile_jsx : Nil
          advance # skip <

          # Self-closing or opening tag
          tag = read_tag_name

          Log.debug { "JSX: found <#{tag}>" }

          props = read_props

          skip_ws

          if looking_at?("/>")
            # Self-closing: <Tag ... />
            advance # /
            advance # >
            emit_h(tag, props, nil)
          elsif current == '>'
            # Opening tag: <Tag ...>children</Tag>
            advance # >

            children = read_children(tag)

            emit_h(tag, props, children)
          end
        end

        private def read_tag_name : String
          start = @pos
          while @pos < @source.size && (current.letter? || current.number? || current == '_' || current == '-' || current == '.')
            advance
          end
          @source[start...@pos]
        end

        private def read_props : Array({String, String})
          props = [] of {String, String}

          loop do
            skip_ws
            break if @pos >= @source.size
            break if current == '>' || looking_at?("/>")

            key = read_prop_name
            break if key.empty?

            skip_ws

            if @pos < @source.size && current == '='
              advance # =
              skip_ws
              value = read_prop_value
              props << {key, value}
            else
              # Boolean prop: <Button disabled />
              props << {key, "true"}
            end
          end

          props
        end

        private def read_prop_name : String
          start = @pos
          while @pos < @source.size && (current.letter? || current.number? || current == '_' || current == '-')
            advance
          end
          @source[start...@pos]
        end

        private def read_prop_value : String
          if current == '"'
            read_string_value('"')
          elsif current == '\''
            read_string_value('\'')
          elsif current == '{'
            read_expression_value
          else
            # Unquoted value
            start = @pos
            while @pos < @source.size && !current.ascii_whitespace? && current != '>' && current != '/'
              advance
            end
            @source[start...@pos]
          end
        end

        private def read_string_value(quote : Char) : String
          advance # opening quote
          start = @pos
          while @pos < @source.size && current != quote
            advance if current == '\\' # skip escaped char
            advance
          end
          value = @source[start...@pos]
          advance # closing quote
          "\"#{value}\""
        end

        private def read_expression_value : String
          advance # {
          depth = 1
          start = @pos

          while @pos < @source.size && depth > 0
            case current
            when '{' then depth += 1
            when '}' then depth -= 1
            when '"', '\''
              skip_string(current)
              next
            when '`'
              skip_template_literal
              next
            when '<'
              # Check for JSX inside expressions like {condition ? <Tag /> : null}
              if depth == 1 && @pos + 1 < @source.size && @source[@pos + 1].uppercase?
                # Emit what we have so far as raw JS
                prefix = @source[start...@pos]

                # Transpile the JSX tag
                child_output = IO::Memory.new
                old_output = @output
                @output = child_output
                transpile_jsx
                @output = old_output

                # Restart tracking from current position
                result = prefix + child_output.to_s

                # Continue reading the rest of the expression
                rest_start = @pos
                while @pos < @source.size && depth > 0
                  case current
                  when '{' then depth += 1
                  when '}' then depth -= 1
                  when '"', '\''
                    skip_string(current)
                    next
                  when '`'
                    skip_template_literal
                    next
                  when '<'
                    if depth == 1 && @pos + 1 < @source.size && @source[@pos + 1].uppercase?
                      mid = @source[rest_start...@pos]
                      old_output2 = @output
                      child_output2 = IO::Memory.new
                      @output = child_output2
                      transpile_jsx
                      @output = old_output2
                      result += mid + child_output2.to_s
                      rest_start = @pos
                      next
                    end
                  end
                  advance if depth > 0
                end

                result += @source[rest_start...@pos]
                advance if @pos < @source.size # closing }
                return result.strip
              end
            end
            advance if depth > 0
          end

          expr = @source[start...@pos]
          advance if @pos < @source.size # closing }
          expr.strip
        end

        # Read children between <Tag> and </Tag>
        private def read_children(parent_tag : String) : Array(String)
          children = [] of String

          loop do
            break if @pos >= @source.size

            # Check for closing tag
            if looking_at?("</")
              advance # <
              advance # /
              closing = read_tag_name
              skip_ws
              advance if @pos < @source.size && current == '>' # >

              if closing != parent_tag
                Log.warn { "JSX: mismatched closing tag, expected </#{parent_tag}>, got </#{closing}>" }
              end
              break
            end

            # Nested JSX element
            if looking_at_jsx?
              child_output = IO::Memory.new
              old_output = @output
              @output = child_output
              transpile_jsx
              @output = old_output
              children << child_output.to_s
              # JS expression in braces
            elsif current == '{'
              expr = read_expression_value
              children << expr unless expr.empty?
              # Text content
            else
              text = read_text_content
              unless text.strip.empty?
                escaped = text.strip.gsub("\\", "\\\\").gsub("\"", "\\\"").gsub("\n", "\\n")
                children << "\"#{escaped}\""
              end
            end
          end

          children
        end

        private def read_text_content : String
          start = @pos
          while @pos < @source.size && current != '<' && current != '{'
            advance
          end
          @source[start...@pos]
        end

        # Emit: h("Tag", { key: value, ... }, child1, child2)
        private def emit_h(tag : String, props : Array({String, String}), children : Array(String)?) : Nil
          # Known native GTK widgets get quoted strings, everything else is a component reference
          native_widgets = %w[
            Box Label Button Entry Image Frame Tab ListBox ScrolledWindow
            HorizontalSeparator VerticalSeparator Switch Spinner ProgressBar
            TextView
          ]

          if native_widgets.includes?(tag)
            @output << "h(\"#{tag}\""
          else
            @output << "h(#{tag}"
          end

          # Props
          if props.empty?
            @output << ", null"
          else
            @output << ", { "
            props.each_with_index do |(key, value), i|
              @output << ", " if i > 0
              @output << "#{key}: #{value}"
            end
            @output << " }"
          end

          # Children
          if children && !children.empty?
            children.each do |child|
              @output << ", "
              @output << child
            end
          end

          @output << ")"
        end

        # Helpers

        private def current : Char
          @source[@pos]
        end

        private def advance : Nil
          @pos += 1
        end

        private def skip_ws : Nil
          while @pos < @source.size && current.ascii_whitespace?
            advance
          end
        end

        private def looking_at?(str : String) : Bool
          return false if @pos + str.size > @source.size
          @source[@pos, str.size] == str
        end

        private def skip_string(quote : Char) : Nil
          advance # opening quote
          while @pos < @source.size
            if current == '\\'
              advance
            elsif current == quote
              advance
              return
            end
            advance
          end
        end

        private def skip_template_literal : Nil
          advance # `
          while @pos < @source.size
            if current == '\\'
              advance
            elsif current == '`'
              advance
              return
            end
            advance
          end
        end
      end
    end
  end
end
