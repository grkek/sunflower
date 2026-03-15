module Sunflower
  module JavaScript
    module Message
      struct Exception
        include JSON::Serializable

        @[JSON::Field(key: "message")]
        property message : String = "No message was provided"

        @[JSON::Field(key: "backtrace")]
        property backtrace : Array(String)

        def initialize(@message : String, @backtrace : Array(String))
        end
      end
    end
  end
end
