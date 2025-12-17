defmodule Colorhymn.Perception do
  @moduledoc """
  Comprehensive multi-dimensional perception of log character.

  Captures the full "feel" of a log across temporal, structural, semantic,
  and domain-specific dimensions. All scores are continuous floats.
  """

  defstruct [
    # ══════════════════════════════════════════════════════════════════════════
    # TEMPORAL — How events flow through time
    # ══════════════════════════════════════════════════════════════════════════
    burstiness: 0.5,            # 0 = sparse (long gaps), 1 = rapid-fire
    regularity: 0.5,            # 0 = erratic, 1 = clockwork
    acceleration: 0.0,          # -1 = slowing down, 0 = steady, +1 = speeding up
    temporal_concentration: 0.5, # 0 = front-loaded, 0.5 = uniform, 1 = back-loaded
    temporal_entropy: 0.5,      # 0 = predictable rhythm, 1 = chaotic timing

    # ══════════════════════════════════════════════════════════════════════════
    # STRUCTURAL — The shape of lines and blocks
    # ══════════════════════════════════════════════════════════════════════════
    line_length_variance: 0.5,  # 0 = uniform lengths, 1 = highly varied
    structure_consistency: 0.5, # 0 = chaotic format, 1 = consistent format
    nesting_depth: 0.0,         # 0 = flat, 1 = deeply nested
    whitespace_ratio: 0.5,      # 0 = dense, 1 = spacious
    block_regularity: 0.5,      # 0 = no clear blocks, 1 = clear block structure

    # ══════════════════════════════════════════════════════════════════════════
    # DENSITY — Information concentration
    # ══════════════════════════════════════════════════════════════════════════
    token_density: 0.5,         # tokens per line (normalized)
    entity_density: 0.5,        # entities (IPs, domains, etc.) per line
    information_density: 0.5,   # unique tokens / total tokens
    noise_ratio: 0.5,           # 0 = all signal, 1 = mostly noise/boilerplate

    # ══════════════════════════════════════════════════════════════════════════
    # REPETITION — Patterns and uniqueness
    # ══════════════════════════════════════════════════════════════════════════
    uniqueness: 0.5,            # 0 = highly repetitive, 1 = all unique
    template_ratio: 0.5,        # 0 = no templates, 1 = all templated
    pattern_recurrence: 0.5,    # 0 = no recurring patterns, 1 = strong patterns
    motif_strength: 0.5,        # strength of dominant recurring motif

    # ══════════════════════════════════════════════════════════════════════════
    # DIALOGUE — Conversational flow and structure
    # ══════════════════════════════════════════════════════════════════════════
    request_response_balance: 0.5, # 0 = all requests, 0.5 = balanced, 1 = all responses
    turn_frequency: 0.5,           # how often direction changes
    monologue_tendency: 0.5,       # 0 = conversational, 1 = monologue/one-sided
    echo_ratio: 0.5,               # how much is echoed/repeated back

    # ══════════════════════════════════════════════════════════════════════════
    # VOLATILITY — Change and stability
    # ══════════════════════════════════════════════════════════════════════════
    field_variance: 0.5,        # how much field values change
    state_churn: 0.5,           # frequency of state transitions
    drift: 0.0,                 # -1 = degrading over time, 0 = stable, +1 = improving
    stability: 0.5,             # 0 = chaotic/unstable, 1 = rock solid

    # ══════════════════════════════════════════════════════════════════════════
    # COMPLEXITY — Cognitive load and structure depth
    # ══════════════════════════════════════════════════════════════════════════
    bracket_depth: 0.0,         # average nesting level (normalized)
    clause_chains: 0.5,         # compound/chained statements
    parse_difficulty: 0.5,      # 0 = trivial to parse, 1 = complex grammar
    cognitive_load: 0.5,        # overall mental effort to understand

    # ══════════════════════════════════════════════════════════════════════════
    # NETWORK — VPN/connectivity specific
    # ══════════════════════════════════════════════════════════════════════════
    session_coherence: 0.5,     # 0 = fragmented/interleaved, 1 = single clean session
    directionality: 0.0,        # -1 = inbound heavy, 0 = balanced, +1 = outbound heavy
    entity_churn: 0.5,          # 0 = same actors throughout, 1 = many different actors
    lifecycle_health: 0.5,      # 0 = stuck states/loops, 1 = clean state transitions
    connection_success_ratio: 0.5, # ratio of successful connections
    handshake_completeness: 0.5    # 0 = incomplete handshakes, 1 = all complete
  ]

  @type t :: %__MODULE__{}

  alias Colorhymn.Perception.{Temporal, Structural, Density, Repetition,
                               Dialogue, Volatility, Complexity, Network}

  @doc """
  Analyze content and produce a full multi-dimensional perception.
  """
  def perceive(content, lines, timestamps) do
    %__MODULE__{}
    |> merge(Temporal.analyze(timestamps, lines))
    |> merge(Structural.analyze(lines))
    |> merge(Density.analyze(lines, content))
    |> merge(Repetition.analyze(lines))
    |> merge(Dialogue.analyze(lines))
    |> merge(Volatility.analyze(lines))
    |> merge(Complexity.analyze(lines, content))
    |> merge(Network.analyze(lines, content))
  end

  defp merge(perception, dimension_map) do
    struct(perception, dimension_map)
  end

  @doc """
  Generate a human-readable summary of the perception.
  """
  def describe(%__MODULE__{} = p) do
    []
    |> maybe_add(describe_tempo(p))
    |> maybe_add(describe_structure(p))
    |> maybe_add(describe_density(p))
    |> maybe_add(describe_character(p))
    |> Enum.reverse()
    |> Enum.join(", ")
  end

  defp maybe_add(list, nil), do: list
  defp maybe_add(list, desc), do: [desc | list]

  defp describe_tempo(%{burstiness: b, regularity: r, acceleration: a}) do
    tempo = cond do
      b > 0.8 -> "rapid-fire"
      b > 0.6 -> "bursty"
      b > 0.4 -> "steady"
      b > 0.2 -> "sparse"
      true -> "very sparse"
    end

    rhythm = cond do
      r > 0.8 -> "clockwork"
      r > 0.6 -> "rhythmic"
      r < 0.3 -> "erratic"
      true -> nil
    end

    accel = cond do
      a > 0.3 -> "accelerating"
      a < -0.3 -> "decelerating"
      true -> nil
    end

    [tempo, rhythm, accel]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      s -> s
    end
  end

  defp describe_structure(%{structure_consistency: sc, nesting_depth: nd}) do
    cond do
      nd > 0.7 -> "deeply nested"
      sc > 0.8 -> "well-structured"
      sc < 0.3 -> "chaotic structure"
      true -> nil
    end
  end

  defp describe_density(%{information_density: id, noise_ratio: nr}) do
    cond do
      nr > 0.7 -> "noisy"
      id > 0.8 -> "information-dense"
      id < 0.2 -> "sparse content"
      true -> nil
    end
  end

  defp describe_character(%{session_coherence: sc, lifecycle_health: lh, uniqueness: u}) do
    cond do
      sc < 0.3 -> "fragmented sessions"
      lh < 0.3 -> "troubled lifecycle"
      u < 0.2 -> "highly repetitive"
      u > 0.9 -> "highly varied"
      true -> nil
    end
  end
end
