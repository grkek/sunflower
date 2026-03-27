require "../../src/sunflower"

Log.setup do |c|
  backend = Log::IOBackend.new(STDERR, formatter: Log::ShortFormat, dispatcher: :sync)
  c.bind("*", :debug, backend)
end

# Maybe implement a callback that will notify the state that the canvas has been filled
spawn do
  loop do
    sleep 1.seconds

    viewport = Sunflower::JavaScript::Engine
      .instance
      .scene_view
      .registry
      .["viewport"]?

    break if viewport
  end
end

builder = Sunflower::Builder.new
builder.build_from_file(File.join(__DIR__, "src", "index.html"))
