module Sunflower
  module Parser
    class Tokenizer
      include Elements

      Log = ::Log.for(self)

      property custom_components = {} of String => Node

      @source : String
      @pos : Int32 = 0
      @line : Int32 = 1
      @col : Int32 = 1

      def initialize(@source : String)
      end

      # Public API

      def parse_nodes : Array(Node)
        nodes = [] of Node

        loop do
          skip_whitespace

          break if eof?
          break if looking_at?("</")

          if node = parse_node
            nodes << node
          end
        end

        nodes
      end

      # Node parsing

      private def parse_node : Node?
        if looking_at?("<!--")
          parse_comment
          nil
        elsif looking_at?("<")
          parse_element
        else
          parse_text
        end
      end

      private def parse_text : Node
        content = consume_until { |c| c == '<' }
        Text.new(content)
      end

      private def parse_comment : Nil
        expect_string("<!--")
        consume_until_string("-->")
        expect_string("-->")
      end

      # ameba:disable Metrics/CyclomaticComplexity
      private def parse_element : Node?
        expect('<')
        tag_name = parse_tag_name

        if tag_name.empty?
          error("Expected tag name after '<'")
        end

        attributes = parse_attributes
        skip_whitespace

        # Self-closing: <Tag ... />
        if looking_at?("/>")
          advance # /
          advance # >
          return create_self_closing(tag_name, attributes)
        end

        expect('>')

        # Void elements that can also be written as <Tag>...</Tag> but contain no children
        # (Script with src is self-closing-like, but we still allow children for inline content)

        children = parse_nodes

        # Closing tag
        expect_string("</")
        closing_name = parse_tag_name
        skip_whitespace
        expect('>')

        if closing_name != tag_name
          error("Mismatched closing tag: expected </#{tag_name}>, got </#{closing_name}>")
        end

        create_element(tag_name, attributes, children)
      end

      # Attribute parsing

      private def parse_attributes : Hash(String, JSON::Any)
        attrs = {} of String => JSON::Any

        loop do
          skip_whitespace
          break if eof?

          Log.debug { "parse_attributes: peek='#{peek}' pos=#{@pos} line=#{@line} col=#{@col}" }
          break if peek == '>' || looking_at?("/>")

          key = parse_attribute_name
          Log.debug { "parse_attributes: key='#{key}'" }

          if key.empty?
            error("Expected attribute name, got '#{peek}'")
          end

          skip_whitespace

          if !eof? && peek == '='
            advance # =
            skip_whitespace
            Log.debug { "parse_attributes: parsing value for '#{key}', peek='#{peek}'" }
            value = parse_attribute_value
            Log.debug { "parse_attributes: #{key}=#{value}" }
            attrs[key] = value
          else
            Log.debug { "parse_attributes: #{key} (boolean)" }
            attrs[key] = JSON::Any.new(true)
          end
        end

        Log.debug { "parse_attributes: result=#{attrs}" }
        attrs
      end

      private def parse_attribute_name : String
        consume_while { |c| c.letter? || c.number? || c == '-' || c == '_' || c == ':' || c == '@' || c == '.' }
      end

      private def parse_attribute_value : JSON::Any
        if eof?
          error("Unexpected end of input while parsing attribute value")
        end

        case peek
        when '"'
          parse_quoted_string('"')
        when '\''
          parse_quoted_string('\'')
        when '{'
          # Future JSX: parse expression
          # For now, read until matching }
          parse_brace_expression
        else
          parse_unquoted_value
        end
      end

      private def parse_quoted_string(quote : Char) : JSON::Any
        advance # opening quote
        value = String.build do |io|
          loop do
            if eof?
              error("Unterminated string literal")
            end

            c = peek

            if c == '\\'
              advance
              if eof?
                error("Unterminated escape sequence")
              end
              io << parse_escape_sequence
            elsif c == quote
              break
            else
              io << c
              advance
            end
          end
        end
        advance # closing quote
        coerce_value(value)
      end

      # Coerces a string value to the appropriate JSON type
      private def coerce_value(value : String) : JSON::Any
        case value
        when "true"  then JSON::Any.new(true)
        when "false" then JSON::Any.new(false)
        when "null"  then JSON::Any.new(nil)
        else
          if value.matches?(/^-?\d+$/)
            JSON::Any.new(value.to_i64)
          elsif value.matches?(/^-?\d+\.\d+$/)
            JSON::Any.new(value.to_f64)
          else
            JSON::Any.new(value)
          end
        end
      end

      private def parse_escape_sequence : Char
        c = peek
        advance
        case c
        when 'n'  then '\n'
        when 't'  then '\t'
        when 'r'  then '\r'
        when '\\' then '\\'
        when '"'  then '"'
        when '\'' then '\''
        else           c
        end
      end

      private def parse_unquoted_value : JSON::Any
        word = consume_while { |c| !c.ascii_whitespace? && c != '>' && c != '/' && c != '"' && c != '\'' }

        # Try to parse as JSON literal (true, false, numbers)
        case word
        when "true"  then JSON::Any.new(true)
        when "false" then JSON::Any.new(false)
        when "null"  then JSON::Any.new(nil)
        else
          if word.matches?(/^-?\d+$/)
            JSON::Any.new(word.to_i64)
          elsif word.matches?(/^-?\d+\.\d+$/)
            JSON::Any.new(word.to_f64)
          else
            JSON::Any.new(word)
          end
        end
      end

      private def parse_brace_expression : JSON::Any
        advance # {
        depth = 1
        expr = String.build do |io|
          loop do
            if eof?
              error("Unterminated brace expression")
            end

            c = peek
            if c == '{'
              depth += 1
            elsif c == '}'
              depth -= 1
              break if depth == 0
            end

            io << c
            advance
          end
        end
        advance # }
        # Store as a special expression marker for future JSX support
        JSON::Any.new(expr.strip)
      end

      # Tag name parsing

      private def parse_tag_name : String
        consume_while { |c| c.letter? || c.number? || c == '-' || c == '_' || c == '.' }
      end

      # Element creation

      private def create_self_closing(tag_name : String, attributes : Hash(String, JSON::Any)) : Node?
        case tag_name
        when "Import"
          begin
            custom_components[attributes["as"].to_s] = Import.new(attributes)
          rescue
            error("Import element requires an 'as' attribute")
          end
          nil
        when "Script"              then Script.new(attributes)
        when "StyleSheet"          then StyleSheet.new(attributes)
        when "Box"                 then Box.new(attributes)
        when "Frame"               then Frame.new(attributes)
        when "ListBox"             then ListBox.new(attributes)
        when "ScrolledWindow"      then ScrolledWindow.new(attributes)
        when "Entry"               then Entry.new(attributes)
        when "Spinner"             then Spinner.new(attributes)
        when "ProgressBar"         then ProgressBar.new(attributes)
        when "Image"               then Image.new(attributes)
        when "Label"               then Label.new(attributes)
        when "Button"              then Button.new(attributes)
        when "VerticalSeparator"   then VerticalSeparator.new(attributes)
        when "HorizontalSeparator" then HorizontalSeparator.new(attributes)
        when "Switch"              then Switch.new(attributes)
        else
          resolve_custom_or_error(tag_name, attributes, [] of Node)
        end
      end

      private def create_element(tag_name : String, attributes : Hash(String, JSON::Any), children : Array(Node)) : Node?
        case tag_name
        when "Script"         then Script.new(attributes, children)
        when "StyleSheet"     then StyleSheet.new(attributes, children)
        when "Application"    then Application.new(attributes, children)
        when "Window"         then Window.new(attributes, children)
        when "Frame"          then Frame.new(attributes, children)
        when "Box"            then Box.new(attributes, children)
        when "ListBox"        then ListBox.new(attributes, children)
        when "ScrolledWindow" then ScrolledWindow.new(attributes, children)
        when "Tab"            then Tab.new(attributes, children)
        when "EventBox"       then EventBox.new(attributes, children)
        when "Button"         then Button.new(attributes, children)
        when "Label"          then Label.new(attributes, children)
        when "TextView"       then TextView.new(attributes, children)
        when "Export"         then Export.new(attributes, children)
        else
          resolve_custom_or_error(tag_name, attributes, children)
        end
      end

      private def resolve_custom_or_error(tag_name : String, attributes : Hash(String, JSON::Any), children : Array(Node)) : Node
        if custom = custom_components[tag_name]?
          child = custom.as(Generic)
          child.attributes.merge!(attributes)
          child.children.concat(children)
          child
        else
          # Suggest similar tag names for typos
          known_tags = %w[
            Application Window Box Frame ListBox ScrolledWindow Tab EventBox
            Button Label Entry TextView Image Switch Spinner ProgressBar
            Script StyleSheet Export Import VerticalSeparator HorizontalSeparator
          ]

          suggestions = known_tags
            .map { |t| {t, Levenshtein.distance(tag_name, t)} }
            .select { |_, d| d <= 3 }
            .sort_by { |_, d| d }
            .map(&.first)

          msg = "Unknown element <#{tag_name}>"
          msg += ". Did you mean: #{suggestions.join(", ")}?" unless suggestions.empty?

          error(msg)
        end
      end

      # Low-level scanner

      private def peek : Char
        @source[@pos]
      end

      private def peek_at(offset : Int32) : Char?
        pos = @pos + offset
        pos < @source.bytesize ? @source[pos] : nil
      end

      private def advance : Char
        c = @source[@pos]
        @pos += 1

        if c == '\n'
          @line += 1
          @col = 1
        else
          @col += 1
        end

        c
      end

      private def eof? : Bool
        @pos >= @source.size
      end

      private def looking_at?(str : String) : Bool
        return false if @pos + str.size > @source.size
        @source[@pos, str.size] == str
      end

      private def expect(c : Char) : Nil
        if eof?
          error("Expected '#{c}', got end of input")
        end

        actual = advance
        if actual != c
          error("Expected '#{c}', got '#{actual}'")
        end
      end

      private def expect_string(str : String) : Nil
        str.each_char do |c|
          expect(c)
        end
      end

      private def skip_whitespace : Nil
        while !eof? && peek.ascii_whitespace?
          advance
        end
      end

      private def consume_while(&) : String
        String.build do |io|
          while !eof? && yield peek
            io << advance
          end
        end
      end

      private def consume_until(&) : String
        String.build do |io|
          while !eof? && !(yield peek)
            io << advance
          end
        end
      end

      private def consume_until_string(str : String) : Nil
        while !eof? && !looking_at?(str)
          advance
        end
      end

      # Error reporting

      private def error(message : String) : NoReturn
        context = extract_context

        full_message = String.build do |io|
          io << "Parse error at line #{@line}, column #{@col}: #{message}\n"
          io << context
        end

        Log.error { full_message }
        raise Exceptions::ParserException.new(full_message)
      end

      private def extract_context : String
        # Find the start and end of the current line
        line_start = @pos
        while line_start > 0 && @source[line_start - 1] != '\n'
          line_start -= 1
        end

        line_end = @pos
        while line_end < @source.bytesize && @source[line_end] != '\n'
          line_end += 1
        end

        line_content = @source[line_start...line_end]
        col_in_line = @pos - line_start

        String.build do |io|
          io << "  #{line_content}\n"
          io << "  " << " " * col_in_line << "^\n"
        end
      end
    end
  end
end
