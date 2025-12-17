defmodule Colorhymn.CLI do
  @moduledoc """
  Command-line interface for Colorhymn.

  Usage:
    colorhymn [options] <file>
    colorhymn [options] --stdin

  Options:
    --format=ansi    Output with ANSI colors (default, for terminal)
    --format=json    Output JSON for frontends
    --format=html    Output HTML with inline styles
    --dither         Enable organic color dithering
    --flow           Enable flowing temperature (colors shift through log)
    --regions        Enable per-region temperature analysis (with --flow)
    --theme=NAME     Color theme (default: rainbow)
                     Options: rainbow, monochrome, temp-lock-warm,
                     temp-lock-cool, terminal, high-contrast, semantic
    --intensity=N    Dither intensity 0.5-3.0 (default: 1.0)
    --tint=N         Hue offset in degrees (-180 to 180) to shift palette
    --sat=N          Saturation multiplier (0.5=muted, 1.5=vivid, default: 1.0)
    --contrast=N     Contrast multiplier (0.5=flat, 1.5=punchy, default: 1.0)
    --no-line-nums   Hide line numbers
    --help           Show this help
  """

  alias Colorhymn.{FirstSight, Expression, Flow}
  alias Colorhymn.Expression.{Color, Theme}

  @default_opts %{
    format: :ansi,
    dither: false,
    flow: false,
    regions: false,
    theme: :rainbow,
    intensity: 1.0,
    tint: 0.0,
    sat: 1.0,
    contrast: 1.0,
    line_nums: true
  }

  def main(args) do
    case parse_args(args) do
      {:ok, opts, [file]} -> process_file(file, opts)
      {:ok, opts, []} when opts.stdin -> process_stdin(opts)
      {:help} -> usage()
      {:error, msg} ->
        IO.puts(:stderr, "Error: #{msg}")
        usage()
        System.halt(1)
      _ ->
        usage()
        System.halt(1)
    end
  end

  defp parse_args(args) do
    parse_args(args, @default_opts, [])
  end

  defp parse_args([], opts, files) do
    {:ok, opts, Enum.reverse(files)}
  end

  defp parse_args(["--help" | _], _opts, _files), do: {:help}
  defp parse_args(["-h" | _], _opts, _files), do: {:help}

  defp parse_args(["--stdin" | rest], opts, files) do
    parse_args(rest, Map.put(opts, :stdin, true), files)
  end

  defp parse_args(["--dither" | rest], opts, files) do
    parse_args(rest, Map.put(opts, :dither, true), files)
  end

  defp parse_args(["--flow" | rest], opts, files) do
    parse_args(rest, Map.put(opts, :flow, true), files)
  end

  defp parse_args(["--regions" | rest], opts, files) do
    parse_args(rest, Map.put(opts, :regions, true), files)
  end

  defp parse_args(["--theme=" <> name | rest], opts, files) do
    case Theme.parse(name) do
      {:ok, theme} -> parse_args(rest, Map.put(opts, :theme, theme), files)
      {:error, msg} -> {:error, msg}
    end
  end

  defp parse_args(["--no-line-nums" | rest], opts, files) do
    parse_args(rest, Map.put(opts, :line_nums, false), files)
  end

  defp parse_args(["--format=" <> format | rest], opts, files) do
    case format do
      "ansi" -> parse_args(rest, Map.put(opts, :format, :ansi), files)
      "json" -> parse_args(rest, Map.put(opts, :format, :json), files)
      "html" -> parse_args(rest, Map.put(opts, :format, :html), files)
      _ -> {:error, "Unknown format: #{format}"}
    end
  end

  defp parse_args(["--intensity=" <> val | rest], opts, files) do
    case Float.parse(val) do
      {n, _} -> parse_args(rest, Map.put(opts, :intensity, n), files)
      :error -> {:error, "Invalid intensity: #{val}"}
    end
  end

  defp parse_args(["--tint=" <> val | rest], opts, files) do
    case Float.parse(val) do
      {n, _} -> parse_args(rest, Map.put(opts, :tint, n), files)
      :error -> {:error, "Invalid tint: #{val}"}
    end
  end

  defp parse_args(["--sat=" <> val | rest], opts, files) do
    case Float.parse(val) do
      {n, _} -> parse_args(rest, Map.put(opts, :sat, n), files)
      :error -> {:error, "Invalid sat: #{val}"}
    end
  end

  defp parse_args(["--contrast=" <> val | rest], opts, files) do
    case Float.parse(val) do
      {n, _} -> parse_args(rest, Map.put(opts, :contrast, n), files)
      :error -> {:error, "Invalid contrast: #{val}"}
    end
  end

  defp parse_args(["-" <> _ = flag | _], _opts, _files) do
    {:error, "Unknown option: #{flag}"}
  end

  defp parse_args([file | rest], opts, files) do
    parse_args(rest, opts, [file | files])
  end

  # ============================================================================
  # Processing
  # ============================================================================

  defp process_file(file_path, opts) do
    case File.read(file_path) do
      {:ok, content} ->
        process_content(content, Path.basename(file_path), opts)
      {:error, reason} ->
        IO.puts(:stderr, "Error reading file: #{reason}")
        System.halt(1)
    end
  end

  defp process_stdin(opts) do
    content = IO.read(:stdio, :eof)
    process_content(content, "stdin", opts)
  end

  defp process_content(content, filename, opts) do
    sight = FirstSight.perceive(content, filename)
    lines = String.split(content, "\n")

    # In flow mode, calculate per-line temperature; otherwise single palette
    if opts.flow do
      if opts.regions do
        # Get full region-aware analysis
        region_data = Flow.analyze_with_regions(lines)

        case opts.format do
          :ansi -> output_ansi_regions(lines, region_data, sight, filename, opts)
          :json -> output_json_regions(lines, region_data, sight, filename, opts)
          :html -> output_html_regions(lines, region_data, sight, filename, opts)
        end
      else
        # Get temperature flow (list of {score, temp_atom} per line)
        flow_data = Flow.analyze(lines)

        case opts.format do
          :ansi -> output_ansi_flow(lines, flow_data, sight, filename, opts)
          :json -> output_json_flow(lines, flow_data, sight, filename, opts)
          :html -> output_html_flow(lines, flow_data, sight, filename, opts)
        end
      end
    else
      palette = Expression.from_perception(sight,
        tint: opts.tint,
        sat: opts.sat,
        contrast: opts.contrast,
        theme: opts.theme
      )

      case opts.format do
        :ansi -> output_ansi(lines, palette, sight, filename, opts)
        :json -> output_json(lines, palette, sight, filename, opts)
        :html -> output_html(lines, palette, sight, filename, opts)
      end
    end
  end

  # ============================================================================
  # ANSI Output (Terminal)
  # ============================================================================

  defp output_ansi(lines, palette, sight, filename, opts) do
    # Header
    temp_color = if sight.temperature_score > 0.6, do: "91", else: "96"
    IO.puts("\e[2m─── \e[0m\e[1m#{filename}\e[0m\e[2m │ temp: \e[0m\e[#{temp_color}m#{format_temp(sight.temperature_score)}\e[0m\e[2m │ #{sight.temperature} ───\e[0m\n")

    # Render lines
    rendered = if opts.dither do
      dither_opts = [intensity: opts.intensity, decay: 0.7, content_influence: 0.4]
      render_lines_dithered_ansi(lines, palette, dither_opts)
    else
      Enum.map(lines, &render_line_ansi(&1, palette))
    end

    # Output with optional line numbers
    rendered
    |> Enum.with_index(1)
    |> Enum.each(fn {line, num} ->
      if opts.line_nums do
        IO.puts("\e[2m#{String.pad_leading("#{num}", 4)}\e[0m │ #{line}")
      else
        IO.puts(line)
      end
    end)
  end

  defp render_line_ansi(line, palette) do
    line
    |> Colorhymn.Tokenizer.tokenize()
    |> Enum.map(fn %{type: type, value: value} ->
      palette_key = Expression.token_to_palette_key(type)
      color = Expression.Palette.color_for(palette, palette_key)
      {r, g, b} = Color.to_rgb(color)
      "\e[38;2;#{r};#{g};#{b}m#{value}\e[0m"
    end)
    |> Enum.join()
  end

  defp render_lines_dithered_ansi(lines, palette, dither_opts) do
    alias Colorhymn.Expression.Dither

    dither = Dither.new(dither_opts)

    {rendered, _} = Enum.map_reduce(lines, dither, fn line, dither_state ->
      tokens = Colorhymn.Tokenizer.tokenize(line)

      {parts, new_dither} = Enum.map_reduce(tokens, dither_state, fn %{type: type, value: value}, acc ->
        palette_key = Expression.token_to_palette_key(type)
        ideal = Expression.Palette.color_for(palette, palette_key)
        {dithered, new_acc} = Dither.dither(acc, ideal, value)
        {r, g, b} = Color.to_rgb(dithered)
        {"\e[38;2;#{r};#{g};#{b}m#{value}\e[0m", new_acc}
      end)

      {Enum.join(parts), Dither.next_line(new_dither)}
    end)

    rendered
  end

  # ============================================================================
  # JSON Output
  # ============================================================================

  defp output_json(lines, palette, sight, filename, opts) do
    line_data = if opts.dither do
      Expression.render_lines_data_dithered(palette, lines, intensity: opts.intensity)
    else
      Enum.map(lines, &Expression.render_line_data(palette, &1))
    end

    json_lines = Enum.map(line_data, fn tokens ->
      tokens
      |> Enum.map(fn {type, value, hex} ->
        ~s(["#{type}","#{escape_json(value)}","#{hex}"])
      end)
      |> then(&"[#{Enum.join(&1, ",")}]")
    end)

    palette_json = palette
    |> Expression.to_hex_map()
    |> Enum.map(fn {k, v} -> ~s("#{k}":"#{v}") end)
    |> Enum.join(",")

    temp_score = Map.get(sight, :temperature_score, 0.5)
    confidence = Map.get(sight, :confidence, 0.8)

    IO.puts(~s({
"metadata":{"filename":"#{escape_json(filename)}","temperature":"#{sight.temperature}","temperature_score":#{Float.round(temp_score, 3)},"confidence":#{confidence},"mood":"#{palette.mood}","warmth":#{Float.round(palette.warmth, 3)},"saturation":#{Float.round(palette.saturation, 3)},"line_count":#{length(lines)},"dithered":#{opts.dither}},
"palette":{#{palette_json}},
"lines":[#{Enum.join(json_lines, ",")}]
}))
  end

  # ============================================================================
  # HTML Output
  # ============================================================================

  defp output_html(lines, palette, sight, filename, opts) do
    bg = Color.to_hex(palette.background)
    fg = Color.to_hex(palette.foreground)

    IO.puts("""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>#{html_escape(filename)} - Colorhymn</title>
      <style>
        body { background: #{bg}; color: #{fg}; font-family: monospace; padding: 20px; margin: 0; }
        .line { white-space: pre; line-height: 1.4; }
        .line-num { color: #{Color.to_hex(palette.muted)}; user-select: none; display: inline-block; width: 4em; text-align: right; margin-right: 1em; }
        .meta { color: #{Color.to_hex(palette.muted)}; margin-bottom: 1em; border-bottom: 1px solid #{Color.to_hex(palette.muted)}; padding-bottom: 0.5em; }
      </style>
    </head>
    <body>
      <div class="meta">#{html_escape(filename)} │ temp: #{format_temp(sight.temperature_score)} │ #{sight.temperature}</div>
    """)

    line_data = if opts.dither do
      Expression.render_lines_data_dithered(palette, lines, intensity: opts.intensity)
    else
      Enum.map(lines, &Expression.render_line_data(palette, &1))
    end

    line_data
    |> Enum.with_index(1)
    |> Enum.each(fn {tokens, num} ->
      line_num = if opts.line_nums, do: ~s(<span class="line-num">#{num}</span>), else: ""
      spans = Enum.map(tokens, fn {_type, value, hex} ->
        ~s(<span style="color:#{hex}">#{html_escape(value)}</span>)
      end)
      IO.puts(~s(  <div class="line">#{line_num}#{Enum.join(spans)}</div>))
    end)

    IO.puts("</body>\n</html>")
  end

  # ============================================================================
  # Flow Mode Output (per-line temperature)
  # ============================================================================

  defp output_ansi_flow(lines, flow_data, sight, filename, opts) do
    # Header shows flow mode
    IO.puts("\e[2m─── \e[0m\e[1m#{filename}\e[0m\e[2m │ \e[0m\e[95m◆ flow mode\e[0m\e[2m │ #{sight.temperature} ───\e[0m\n")

    # Render with per-line palettes
    alias Colorhymn.Expression.Dither

    dither_opts = [intensity: opts.intensity, decay: 0.7, content_influence: 0.4]
    dither = if opts.dither, do: Dither.new(dither_opts), else: nil

    {rendered, _} = lines
    |> Enum.zip(flow_data)
    |> Enum.map_reduce(dither, fn {line, {score, _temp}}, dither_state ->
      # Generate palette for this line's temperature
      palette = palette_for_score(score, sight, opts)

      if dither_state do
        # Dithered rendering
        tokens = Colorhymn.Tokenizer.tokenize(line)
        {parts, new_dither} = Enum.map_reduce(tokens, dither_state, fn %{type: type, value: value}, acc ->
          palette_key = Expression.token_to_palette_key(type)
          ideal = Expression.Palette.color_for(palette, palette_key)
          {dithered, new_acc} = Dither.dither(acc, ideal, value)
          {r, g, b} = Color.to_rgb(dithered)
          {"\e[38;2;#{r};#{g};#{b}m#{value}\e[0m", new_acc}
        end)
        {Enum.join(parts), Dither.next_line(new_dither)}
      else
        # Non-dithered rendering
        {render_line_ansi(line, palette), nil}
      end
    end)

    # Output with line numbers and mini temperature indicator
    rendered
    |> Enum.zip(flow_data)
    |> Enum.with_index(1)
    |> Enum.each(fn {{line, {score, _temp}}, num} ->
      if opts.line_nums do
        temp_char = temp_indicator(score)
        IO.puts("\e[2m#{String.pad_leading("#{num}", 4)}\e[0m #{temp_char} #{line}")
      else
        IO.puts(line)
      end
    end)
  end

  # Generate palette for a specific temperature score
  defp palette_for_score(score, sight, opts) do
    # Create a mock sight with this temperature score
    modified_sight = %{
      sight |
      temperature_score: score,
      temperature: score_to_temp_atom(score)
    }

    Expression.from_perception(modified_sight,
      tint: opts.tint,
      sat: opts.sat,
      contrast: opts.contrast,
      theme: opts.theme
    )
  end

  defp score_to_temp_atom(score) do
    cond do
      score > 0.8 -> :critical
      score > 0.6 -> :troubled
      score > 0.45 -> :uneasy
      score < 0.3 -> :calm
      true -> :neutral
    end
  end

  # Mini temperature indicator character
  defp temp_indicator(score) do
    cond do
      score > 0.85 -> "\e[91m●\e[0m"  # Red dot
      score > 0.7 -> "\e[38;5;208m●\e[0m"  # Orange dot
      score > 0.55 -> "\e[93m●\e[0m"  # Yellow dot
      score > 0.4 -> "\e[37m○\e[0m"  # White circle
      score > 0.25 -> "\e[96m●\e[0m"  # Cyan dot
      true -> "\e[94m●\e[0m"  # Blue dot
    end
  end

  defp output_json_flow(lines, flow_data, sight, filename, opts) do
    # For JSON, include per-line temperature scores
    line_data = lines
    |> Enum.zip(flow_data)
    |> Enum.map(fn {line, {score, _temp}} ->
      palette = palette_for_score(score, sight, opts)
      tokens = Expression.render_line_data(palette, line)
      {tokens, score}
    end)

    json_lines = Enum.map(line_data, fn {tokens, score} ->
      token_json = tokens
      |> Enum.map(fn {type, value, hex} ->
        ~s(["#{type}","#{escape_json(value)}","#{hex}"])
      end)
      |> Enum.join(",")
      ~s({"temp":#{Float.round(score, 3)},"tokens":[#{token_json}]})
    end)

    IO.puts(~s({
"metadata":{"filename":"#{escape_json(filename)}","flow":true,"line_count":#{length(lines)},"dithered":#{opts.dither}},
"lines":[#{Enum.join(json_lines, ",")}]
}))
  end

  defp output_html_flow(lines, flow_data, sight, filename, opts) do
    # Use a neutral palette for page styling
    base_palette = palette_for_score(0.5, sight, opts)
    bg = Color.to_hex(base_palette.background)
    fg = Color.to_hex(base_palette.foreground)

    IO.puts("""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>#{html_escape(filename)} - Colorhymn Flow</title>
      <style>
        body { background: #{bg}; color: #{fg}; font-family: monospace; padding: 20px; margin: 0; }
        .line { white-space: pre; line-height: 1.4; }
        .line-num { color: #666; user-select: none; display: inline-block; width: 4em; text-align: right; margin-right: 0.5em; }
        .temp { display: inline-block; width: 1em; margin-right: 0.5em; }
        .meta { color: #888; margin-bottom: 1em; border-bottom: 1px solid #444; padding-bottom: 0.5em; }
      </style>
    </head>
    <body>
      <div class="meta">#{html_escape(filename)} │ ◆ flow mode</div>
    """)

    lines
    |> Enum.zip(flow_data)
    |> Enum.with_index(1)
    |> Enum.each(fn {{line, {score, _temp}}, num} ->
      palette = palette_for_score(score, sight, opts)
      tokens = Expression.render_line_data(palette, line)

      line_num = if opts.line_nums, do: ~s(<span class="line-num">#{num}</span>), else: ""
      temp_color = temp_to_html_color(score)
      temp_span = ~s(<span class="temp" style="color:#{temp_color}">●</span>)
      spans = Enum.map(tokens, fn {_type, value, hex} ->
        ~s(<span style="color:#{hex}">#{html_escape(value)}</span>)
      end)
      IO.puts(~s(  <div class="line">#{line_num}#{temp_span}#{Enum.join(spans)}</div>))
    end)

    IO.puts("</body>\n</html>")
  end

  defp temp_to_html_color(score) do
    cond do
      score > 0.85 -> "#ff4444"
      score > 0.7 -> "#ff8800"
      score > 0.55 -> "#ffcc00"
      score > 0.4 -> "#888888"
      score > 0.25 -> "#44cccc"
      true -> "#4488ff"
    end
  end

  # ============================================================================
  # Region-Aware Output (per-region temperatures)
  # ============================================================================

  defp output_ansi_regions(_lines, region_data, sight, filename, opts) do
    # Header shows region mode
    IO.puts("\e[2m─── \e[0m\e[1m#{filename}\e[0m\e[2m │ \e[0m\e[95m◆ flow+regions\e[0m\e[2m │ #{sight.temperature} ───\e[0m\n")

    alias Colorhymn.Expression.Dither

    dither_opts = [intensity: opts.intensity, decay: 0.7, content_influence: 0.4]
    dither = if opts.dither, do: Dither.new(dither_opts), else: nil

    {rendered, _} = Enum.map_reduce(region_data, dither, fn data, dither_state ->
      {score, _temp} = data.line_temp
      palette = palette_for_score(score, sight, opts)
      line = data.line

      if dither_state do
        tokens = Colorhymn.Tokenizer.tokenize(line)
        {parts, new_dither} = Enum.map_reduce(tokens, dither_state, fn %{type: type, value: value}, acc ->
          palette_key = Expression.token_to_palette_key(type)
          ideal = Expression.Palette.color_for(palette, palette_key)
          {dithered, new_acc} = Dither.dither(acc, ideal, value)
          {r, g, b} = Color.to_rgb(dithered)
          {"\e[38;2;#{r};#{g};#{b}m#{value}\e[0m", new_acc}
        end)
        {Enum.join(parts), Dither.next_line(new_dither)}
      else
        {render_line_ansi(line, palette), nil}
      end
    end)

    # Output with line numbers and region temperature indicators
    rendered
    |> Enum.zip(region_data)
    |> Enum.with_index(1)
    |> Enum.each(fn {{line, data}, num} ->
      if opts.line_nums do
        {score, _temp} = data.line_temp
        temp_char = temp_indicator(score)

        # Show region temps in a compact format
        region_info = format_region_temps(data.region_temps)
        IO.puts("\e[2m#{String.pad_leading("#{num}", 4)}\e[0m #{temp_char} #{line}\e[2m#{region_info}\e[0m")
      else
        IO.puts(line)
      end
    end)
  end

  defp format_region_temps(region_temps) when map_size(region_temps) == 0, do: ""
  defp format_region_temps(region_temps) do
    parts = region_temps
    |> Enum.map(fn {type, temp} ->
      short_type = case type do
        :timestamp -> "ts"
        :log_level -> "lv"
        :message -> "msg"
        :key_value -> "kv"
        :component -> "cmp"
        :bracket -> "br"
        _ -> "?"
      end
      "#{short_type}:#{Float.round(temp, 2)}"
    end)
    |> Enum.join(" ")

    " [#{parts}]"
  end

  defp output_json_regions(_lines, region_data, _sight, filename, opts) do
    json_lines = Enum.map(region_data, fn data ->
      {score, temp_atom} = data.line_temp

      # Format regions
      regions_json = data.regions
      |> Enum.map(fn r ->
        ~s({"type":"#{r.type}","start":#{r.start},"length":#{r.length},"value":"#{escape_json(r.value)}"})
      end)
      |> Enum.join(",")

      # Format region temps
      region_temps_json = data.region_temps
      |> Enum.map(fn {k, v} -> ~s("#{k}":#{Float.round(v, 3)}) end)
      |> Enum.join(",")

      # Format group info
      group_json = case data.group do
        nil -> "null"
        g -> ~s({"type":"#{g.type}","start":#{g.start_line},"end":#{g.end_line},"lines":#{g.line_count}})
      end

      ~s({"line_num":#{data.line_num},"temp":#{Float.round(score, 3)},"temp_atom":"#{temp_atom}","region_temps":{#{region_temps_json}},"regions":[#{regions_json}],"group":#{group_json}})
    end)

    IO.puts(~s({
"metadata":{"filename":"#{escape_json(filename)}","flow":true,"regions":true,"line_count":#{length(region_data)},"dithered":#{opts.dither}},
"lines":[#{Enum.join(json_lines, ",")}]
}))
  end

  defp output_html_regions(_lines, region_data, sight, filename, opts) do
    base_palette = palette_for_score(0.5, sight, opts)
    bg = Color.to_hex(base_palette.background)
    fg = Color.to_hex(base_palette.foreground)

    IO.puts("""
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>#{html_escape(filename)} - Colorhymn Regions</title>
      <style>
        body { background: #{bg}; color: #{fg}; font-family: monospace; padding: 20px; margin: 0; }
        .line { white-space: pre; line-height: 1.4; }
        .line-num { color: #666; user-select: none; display: inline-block; width: 4em; text-align: right; margin-right: 0.5em; }
        .temp { display: inline-block; width: 1em; margin-right: 0.5em; }
        .region-temps { color: #666; font-size: 0.8em; margin-left: 1em; }
        .meta { color: #888; margin-bottom: 1em; border-bottom: 1px solid #444; padding-bottom: 0.5em; }
        .group-start { border-left: 2px solid #666; padding-left: 0.5em; }
      </style>
    </head>
    <body>
      <div class="meta">#{html_escape(filename)} │ ◆ flow+regions</div>
    """)

    region_data
    |> Enum.with_index(1)
    |> Enum.each(fn {data, num} ->
      {score, _temp} = data.line_temp
      palette = palette_for_score(score, sight, opts)
      tokens = Expression.render_line_data(palette, data.line)

      line_num = if opts.line_nums, do: ~s(<span class="line-num">#{num}</span>), else: ""
      temp_color = temp_to_html_color(score)
      temp_span = ~s(<span class="temp" style="color:#{temp_color}">●</span>)

      # Group styling
      group_class = case data.group do
        %{type: type, start_line: start} when start == data.line_num and type != :single ->
          " group-start"
        _ -> ""
      end

      spans = Enum.map(tokens, fn {_type, value, hex} ->
        ~s(<span style="color:#{hex}">#{html_escape(value)}</span>)
      end)

      # Region temps tooltip
      region_info = if map_size(data.region_temps) > 0 do
        temps = data.region_temps
        |> Enum.map(fn {k, v} -> "#{k}:#{Float.round(v, 2)}" end)
        |> Enum.join(" ")
        ~s(<span class="region-temps">[#{temps}]</span>)
      else
        ""
      end

      IO.puts(~s(  <div class="line#{group_class}">#{line_num}#{temp_span}#{Enum.join(spans)}#{region_info}</div>))
    end)

    IO.puts("</body>\n</html>")
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp format_temp(score) when is_number(score) do
    bar_width = 10
    filled = round(score * bar_width)
    empty = bar_width - filled
    "#{String.duplicate("█", filled)}#{String.duplicate("░", empty)} #{Float.round(score, 2)}"
  end
  defp format_temp(_), do: "?"

  defp escape_json(s) do
    s
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp html_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp usage do
    IO.puts(:stderr, @moduledoc)
  end
end
