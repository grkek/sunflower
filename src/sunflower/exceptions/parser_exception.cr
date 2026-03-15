module Sunflower
  module Exceptions
    class ParserException < Exception
      def initialize(message : String)
        super(message)
      end
    end
  end
end
