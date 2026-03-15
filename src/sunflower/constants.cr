module Sunflower
  module Constants
    ENVIRONMENT          = ENV["ENVIRONMENT"]? || "development"
    STATELESS_COMPONENTS = ["Export", "Import", "Script", "StyleSheet", "Text"]
  end
end
