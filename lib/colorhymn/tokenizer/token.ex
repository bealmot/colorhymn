defmodule Colorhymn.Tokenizer.Token do
  @moduledoc """
  A tagged span within a log line.

  Each token has:
  - type: semantic category (:timestamp, :ip_address, :keyword, etc.)
  - value: the actual text
  - start: byte offset in original line
  - length: byte length of the token
  """

  defstruct [:type, :value, :start, :length]

  @type token_type ::
    :timestamp | :ip_address | :ipv6_address | :domain | :path | :url |
    :uuid | :mac_address | :email |
    :number | :hex_number | :port |
    :string | :keyword | :log_level |
    :identifier | :operator | :bracket |
    :key | :equals |
    :text

  @type t :: %__MODULE__{
    type: token_type(),
    value: String.t(),
    start: non_neg_integer(),
    length: non_neg_integer()
  }

  def new(type, value, start) do
    %__MODULE__{
      type: type,
      value: value,
      start: start,
      length: byte_size(value)
    }
  end

  def end_pos(%__MODULE__{start: start, length: length}) do
    start + length
  end
end
