require "../../src/sunflower"

Log.setup do |c|
  backend = Log::IOBackend.new(STDERR, formatter: Log::ShortFormat, dispatcher: :sync)
  c.bind("*", :info, backend)
  c.bind("medusa.sandbox", :info, backend)
end

builder = Sunflower::Builder.new
builder.build_from_file(File.join(__DIR__, "src", "index.html"))
