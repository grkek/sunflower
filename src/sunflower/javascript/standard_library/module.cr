module Sunflower
  module JavaScript
    module StandardLibrary
      abstract class Module
        Log = ::Log.for(self)

        abstract def register(sandbox : Medusa::Sandbox, engine : Engine) : Nil
      end
    end
  end
end
