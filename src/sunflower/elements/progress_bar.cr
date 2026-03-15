require "./node"
require "./generic"

module Sunflower
  module Elements
    class ProgressBar < Generic
      getter kind : String = "ProgressBar"
      getter attributes : Hash(String, JSON::Any)

      def initialize(@attributes, @children = [] of Node)
        super(@kind, @attributes, @children)
      end
    end
  end
end
