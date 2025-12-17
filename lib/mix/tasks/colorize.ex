defmodule Mix.Tasks.Colorize do
  @moduledoc "Colorize a log file and output JSON"
  use Mix.Task

  alias Colorhymn.{FirstSight, Expression}

  @shortdoc "Colorize a log file"
  def run([file_path]) do
    {:ok, content} = File.read(file_path)
    output_json(content, Path.basename(file_path))
  end

  def run(["--stdin"]) do
    content = IO.read(:stdio, :eof)
    output_json(content, "stdin")
  end

  def run(_), do: IO.puts(:stderr, "Usage: mix colorize <file> | mix colorize --stdin")

  defp output_json(content, filename) do
    sight = FirstSight.perceive(content, filename)
    palette = Expression.from_perception(sight)

    lines = content
    |> String.split("\n")
    |> Enum.map(fn line ->
      Expression.render_line_data(palette, line)
      |> Enum.map(fn {type, value, hex} ->
        # Simple JSON array: [type, value, color]
        ~s(["#{type}","#{escape_json(value)}","#{hex}"])
      end)
      |> then(&"[#{Enum.join(&1, ",")}]")
    end)

    hex_map = Expression.to_hex_map(palette)
    palette_json = hex_map
    |> Enum.map(fn {k, v} -> ~s("#{k}":"#{v}") end)
    |> Enum.join(",")

    temp_score = Map.get(sight, :temperature_score, 0.5)

    IO.puts(~s({
"metadata":{"filename":"#{escape_json(filename)}","temperature":"#{sight.temperature}","temperature_score":#{Float.round(temp_score, 3)},"mood":"#{palette.mood}","warmth":#{Float.round(palette.warmth, 3)},"saturation":#{Float.round(palette.saturation, 3)},"line_count":#{length(lines)}},
"palette":{#{palette_json}},
"lines":[#{Enum.join(lines, ",")}]
}))
  end

  defp escape_json(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
