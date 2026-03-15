module Sunflower
  module Attributes
    class Container
      include JSON::Serializable

      @[JSON::Field(key: "containerLabel")]
      property container_label : String = "Untitled"

      @[JSON::Field(key: "expand")]
      property? expand : Bool = false

      @[JSON::Field(key: "fill")]
      property? fill : Bool = false

      @[JSON::Field(key: "padding")]
      property padding : Int32 = 0

      @[JSON::Field(key: "homogeneous")]
      property? homogeneous : Bool = false
    end
  end
end
