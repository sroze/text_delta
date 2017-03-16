defmodule TextDelta.Delta do
  @moduledoc """
  Delta is a format used to describe documents and changes.

  Delta can describe any rich text changes or a document itself, preserving all the formatting, but
  without locking us to any particular markup language.

  On the ground level, delta is an array of operations (constructed via `TextDelta.Operation`).
  Operations can be `insert`, `retain` or `delete`. None of the operations contain index, meaning
  that delta aways describes document or a change staring from the very beginning.

  Delta can describe both changes to and documents themselves. We can think of a document as an
  artefact of all the changes applied to it. This way, newly imported document can be thinked of as
  simply a sequence of inserts applied to an empty document.

  Deltas are also composable and transformable. This means that a document delta can be composed
  with another delta for that document, resulting in one, often shorter delta.

  Deltas can also be transformed against each other, enabling what is called [Operational
  Transformation][ot] - a way to transform one operation in the context of another one. Operational
  Transformation allows us to build optimistic, non-locking collaborative editing tools.

  ## Examples

    iex> alias TextDelta.Delta
    iex> delta = Delta.new() |> Delta.insert("Gandalf", %{bold: true})
    [%{insert: "Gandalf", attributes: %{bold: true}}]
    iex> delta = delta |> Delta.insert(" the ")
    [%{insert: "Gandalf", attributes: %{bold: true}}, %{insert: " the "}]
    iex> delta |> Delta.insert("Grey", %{color: "#ccc"})
    [%{insert: "Gandalf", attributes: %{bold: true}}, %{insert: " the "}, %{insert: "Grey", attributes: %{color: "#ccc"}}]

  [ot]: https://en.wikipedia.org/wiki/Operational_transformation
  """

  alias TextDelta.{Operation, Attributes}
  alias TextDelta.Delta.Transformation

  @typedoc """
  Delta is a list, consisting of `t:TextDelta.Operation.retain/0`, `t:TextDelta.Operation.insert/0`,
  and `t:TextDelta.Operation.delete/0` operations.
  """
  @type t :: [Operation.t]

  @doc """
  Creates new delta.
  """
  @spec new() :: t
  def new(), do: []

  @doc """
  Creates and appends new insert operation to a given delta.

  Same as with `TextDelta.Operation.insert/2` operation factory itself, attributes are optional.

  As it is actually used under the hood, all rules of `TextDelta.Delta.append/2` apply.

  ## Examples

    iex> alias TextDelta.Delta
    iex> Delta.new() |> Delta.insert("hello", %{bold: true})
    [%{insert: "hello", attributes: %{bold: true}}]
  """
  @spec insert(t, Operation.element, Attributes.t) :: t
  def insert(delta, el, attrs \\ %{}) do
    append(delta, Operation.insert(el, attrs))
  end

  @doc """
  Creates and appends new retain operation to a given delta.

  Same as with `TextDelta.Operation.retain/2` operation factory itself, attributes are optional.

  As it is actually used under the hood, all rules of `TextDelta.Delta.append/2` apply.

  ## Examples

    iex> alias TextDelta.Delta
    iex> Delta.new() |> Delta.retain(5, %{italic: true})
    [%{retain: 5, attributes: %{italic: true}}]
  """
  @spec retain(t, non_neg_integer, Attributes.t) :: t
  def retain(delta, len, attrs \\ %{}) do
    append(delta, Operation.retain(len, attrs))
  end

  @doc """
  Creates and appends new delete operation to a given delta.

  As it is actually used under the hood, all rules of `TextDelta.Delta.append/2` apply.

  ## Examples

    iex> alias TextDelta.Delta
    iex> Delta.new() |> Delta.delete(3)
    [%{delete: 3}]
  """
  @spec delete(t, non_neg_integer) :: t
  def delete(delta, len) do
    append(delta, Operation.delete(len))
  end

  @doc """
  Appends an operation to a given delta.

  Before adding operation to a delta, this function attempts to compact it by applying 2 simple
  rules:

  1. Insert followed by delete is swapped places to ensure that insert always goes first.
  2. Same operations with with the same attributes are merged together.

  These two rules ensure that our deltas are always as short as possible and canonical, making it
  much easier to compare, compose and transform them.

  ## Examples

    iex> operation = TextDelta.Operation.insert("hello")
    iex> TextDelta.Delta.new() |> TextDelta.Delta.append(operation)
    [%{insert: "hello"}]
  """
  @spec append(t, Operation.t) :: t
  def append(delta, op)
  def append(nil, op), do: append([], op)
  def append(delta, nil), do: append(delta, [])
  def append([], op), do: compact(nil, op, [])
  def append(delta, []), do: delta
  def append(delta, op) do
    delta
    |> List.last()
    |> compact(op, Enum.slice(delta, 0..-2))
  end

  @doc """
  Trims trailing retains from the end of a given delta.

  ## Examples

    iex> [%{insert: "hello"}, %{retain: 5}] |> TextDelta.Delta.trim()
    [%{insert: "hello"}]
  """
  @spec trim(t) :: t
  def trim([]), do: []
  def trim(delta) do
    last_operation = List.last(delta)
    case Operation.trimmable?(last_operation) do
      true -> Enum.slice(delta, 0..-2) |> trim()
      false -> delta
    end
  end

  defp compact(op_a, %{insert: ""}, delta) do
    delta ++ List.wrap(op_a)
  end

  defp compact(op_a, %{retain: 0}, delta) do
    delta ++ List.wrap(op_a)
  end

  defp compact(op_a, %{delete: 0}, delta) do
    delta ++ List.wrap(op_a)
  end

  defp compact(nil, op_b, _) do
    List.wrap(op_b)
  end

  defp compact(%{delete: _} = del, %{insert: _} = ins, delta) do
    compacted_insert =
      delta
      |> List.last()
      |> compact(ins, Enum.slice(delta, 0..-2))
    delta
    |> Enum.slice(0..-2)
    |> Kernel.++(compacted_insert)
    |> Kernel.++([del])
  end

  defp compact(op_a, op_b, delta) do
    delta ++ Operation.compact(op_a, op_b)
  end
end