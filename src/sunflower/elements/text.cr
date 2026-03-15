require "./node"

module Sunflower
  module Elements
    class Text < Node
      getter kind : String = "Text"
      getter children : Array(Node) = [] of Node
      getter content : String = ""

      def initialize(content : String = "")
        matches = content.scan(/\${(.*?)}/)

        case matches.size
        when 0
          @content = content
        else
        end
      end
    end
  end
end
