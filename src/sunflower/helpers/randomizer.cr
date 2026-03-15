module Sunflower
  module Helpers
    module Randomizer
      def self.random_string(size : Int = 16, charset : String = "ACDEFGHJKMNPQRTWXYZabcdefghjkmnopqrstwxy")
        charset = charset.chars

        String.build(size) do |io|
          size.times do
            io << charset.sample(Random::DEFAULT)
          end
        end
      end
    end
  end
end
