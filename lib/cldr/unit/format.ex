defmodule Cldr.Unit.Format do
  alias Cldr.Unit

  defmacrop is_grammar(unit) do
    quote do
      is_tuple(unquote(unit))
    end
  end

  @typep grammar ::
           {Unit.translatable_unit(),
            {Unit.grammatical_case(), Cldr.Number.PluralRule.plural_type()}}

  @typep grammar_list :: [grammar, ...]

  @translatable_units Cldr.Unit.known_units()
  @si_keys Cldr.Unit.Prefix.si_keys()
  @power_keys Cldr.Unit.Prefix.power_keys()

  @default_case :nominative
  @default_format :long

  # Direct formatting of the unit since
  # it is translatable directly
  def to_iolist(unit, options \\ [])

  def to_iolist(%Cldr.Unit{unit: name} = unit, options) when name in @translatable_units do
    {locale, backend, format, grammatical_case, gender, plural} = extract_options!(unit, options)
    formats = Cldr.Unit.units_for(locale, format, backend)
    number_format_options = Keyword.merge(unit.format_options, options)
    unit_grammar = {name, {grammatical_case, plural}}

    formatted_number = format_number!(unit, number_format_options)
    unit_pattern = get_unit_pattern!(unit_grammar, formats, grammatical_case, gender, plural)
    Cldr.Substitution.substitute(formatted_number, unit_pattern)
  end

  def to_iolist(%Cldr.Unit{} = unit, options) do
    {locale, backend, format, grammatical_case, gender, plural} = extract_options!(unit, options)
    formats = Cldr.Unit.units_for(locale, format, backend)
    number_format_options = Keyword.merge(unit.format_options, options)
    formatted_number = format_number!(unit, number_format_options)
    grammar = grammar(unit, locale: locale, backend: backend)

    head_pattern =
      to_iolist([hd(grammar)], formats, grammatical_case, gender, plural)

    head =
      Cldr.Substitution.substitute(formatted_number, head_pattern)

    tail =
      to_iolist(tl(grammar), formats, grammatical_case, gender, plural)
      |> extract_unit

    to_iolist([head, tail], formats, grammatical_case, gender, plural)
  end

  def to_iolist([], _formats, _grammatical_case, _gender, _plural) do
    []
  end

  # SI Prefixes
  def to_iolist([{si_prefix, _}, {name, _} | rest], formats, grammatical_case, gender, plural)
      when si_prefix in @si_keys do
    si_pattern =
      get_in(formats, [si_prefix, :unit_prefix_pattern]) ||
        raise(Cldr.Unit.NoPatternError, {si_prefix, grammatical_case, gender, plural})

    unit_pattern =
      get_in(formats, [name, grammatical_case, plural]) ||
        get_in(formats, [name, plural]) ||
        raise(Cldr.Unit.NoPatternError, {name, grammatical_case, gender, plural})

    [merge_SI_prefix(si_pattern, unit_pattern) | rest]
    |> to_iolist(formats, grammatical_case, gender, plural)
  end

  # Power prefixes
  def to_iolist([{power_prefix, _} | rest], formats, grammatical_case, gender, plural)
      when power_prefix in @power_keys do
    power_formats =
      get_in(formats, [power_prefix, :compound_unit_pattern])

    power_pattern =
      get_in(power_formats, [gender, plural, grammatical_case]) ||
        get_in(power_formats, [gender, plural]) ||
        get_in(power_formats, [plural, grammatical_case]) ||
        get_in(power_formats, [plural]) ||
        get_in(power_formats, [@default_case]) ||
        raise(Cldr.Unit.NoPatternError, {power_prefix, grammatical_case, gender, plural})

    IO.inspect(power_pattern, label: "power pattern")

    rest = to_iolist(rest, formats, grammatical_case, gender, plural)
    |> IO.inspect(label: "rest")
    merge_power_prefix(power_pattern, rest)
  end

  # Two grammar units
  def to_iolist([unit_1, unit_2 | rest], formats, grammatical_case, gender, plural)
      when is_grammar(unit_1) do
    times_pattern =
      get_in(formats, [:times, :compound_unit_pattern])

    unit_pattern_1 =
      get_unit_pattern!(unit_1, formats, grammatical_case, gender, plural)

    unit_pattern_2 =
      get_unit_pattern!(unit_2, formats, grammatical_case, gender, plural)
      |> extract_unit

    [Cldr.Substitution.substitute([unit_pattern_1, unit_pattern_2], times_pattern) | rest]
    |> to_iolist(formats, grammatical_case, gender, plural)
  end

  def to_iolist([unit], formats, grammatical_case, gender, plural) when is_grammar(unit) do
    get_unit_pattern!(unit, formats, grammatical_case, gender, plural)
  end

  def to_iolist([pattern_list], _formats, _grammatical_case, _gender, _plural) do
    pattern_list
  end

  # When unit_1 is already in pattern form
  def to_iolist([unit_pattern_1 | rest], formats, grammatical_case, gender, plural) do
    times_pattern =
      get_in(formats, [:times, :compound_unit_pattern])

    unit_pattern_2 =
      to_iolist(rest, formats, grammatical_case, gender, plural)

    Cldr.Substitution.substitute([unit_pattern_1, unit_pattern_2], times_pattern)
  end

  defp get_unit_pattern!(unit, formats, grammatical_case, gender, plural) do
    {name, {unit_case, unit_plural}} = unit
    unit_case = if unit_case == :compound, do: grammatical_case, else: unit_case
    unit_plural = if unit_plural == :compound, do: plural, else: unit_plural

    get_in(formats, [name, unit_case, unit_plural]) ||
      get_in(formats, [name, @default_case, unit_plural]) ||
      raise(Cldr.Unit.NoPatternError, {name, unit_case, gender, unit_plural})
  end

  defp extract_unit([place, string]) when is_integer(place) do
    String.trim(string)
  end

  defp extract_unit([string, place]) when is_integer(place) do
    String.trim(string)
  end

  defp format_number!(unit, options) do
    number_format_options = Keyword.merge(unit.format_options, options)
    Cldr.Number.to_string!(unit.value, number_format_options)
  end

  # Merging power and SI prefixes into a pattern is a heuristic since the
  # underlying data does not convey those rules.

  @merge_SI_prefix ~r/([^\s]+)$/u
  defp merge_SI_prefix([prefix, place], [place, string]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [place, String.replace(string, @merge_SI_prefix, "#{prefix}\\1")]
  end

  defp merge_SI_prefix([prefix, place], [string, place]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [String.replace(string, @merge_SI_prefix, "#{prefix}\\1"), place]
  end

  defp merge_SI_prefix([place, prefix], [place, string]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [place, String.replace(string, @merge_SI_prefix, "#{prefix}\\1")]
  end

  defp merge_SI_prefix([place, prefix], [string, place]) when is_integer(place) do
    string = maybe_downcase(prefix, string)
    [String.replace(string, @merge_SI_prefix, "#{prefix}\\1"), place]
  end

  @merge_power_prefix ~r/([^\s]+)/u
  defp merge_power_prefix([prefix, place], [place, string]) when is_integer(place) do
    [place, String.replace(string, @merge_power_prefix, "#{prefix}\\1")]
  end

  defp merge_power_prefix([prefix, place], [string, place]) when is_integer(place) do
    [String.replace(string, @merge_power_prefix, "#{prefix}\\1"), place]
  end

  defp merge_power_prefix([place, prefix], [place, string]) when is_integer(place) do
    [place, String.replace(string, @merge_power_prefix, "\\1#{prefix}")]
  end

  defp merge_power_prefix([place, prefix], [string, place]) when is_integer(place) do
    [String.replace(string, @merge_power_prefix, "\\1#{prefix}"), place]
  end

  # If the prefix has no trailing whitespace then
  # downcase the string since it will be
  # joined adjacent to the prefix
  defp maybe_downcase(prefix, string) do
    if String.match?(prefix, ~r/\s+$/u) do
      string
    else
      String.downcase(string)
    end
  end

  defp extract_options!(unit, options) do
    {locale, backend} = Cldr.locale_and_backend_from(options)
    unit_backend = Module.concat(backend, :Unit)

    format = Keyword.get(options, :format, @default_format)
    grammatical_case = Keyword.get(options, :case, @default_case)
    gender = Keyword.get(options, :gender, unit_backend.default_gender(locale))
    plural = Cldr.Number.PluralRule.plural_type(unit.value, backend, locale: locale)
    {locale, backend, format, grammatical_case, gender, plural}
  end

  @doc """
  Traverses the components of a unit
  and resolves a list of base units with
  their gramatical case and plural selector
  definitions for a given locale.

  This function relies upon the internal
  representation of units and grammatical features
  and is primarily for the support of
  formatting a function through `Cldr.Unit.to_string/2`.

  ## Arguments

  * `unit` is a `t:Cldr.Unit` or a binary
    unit string

  ## Options

  * `:locale` is any valid locale name returned by `Cldr.known_locale_names/1`
    or a `t:Cldr.LanguageTag` struct.  The default is `Cldr.get_locale/0`

  * `backend` is any module that includes `use Cldr` and therefore
    is a `Cldr` backend module. The default is `Cldr.default_backend!/0`.

  ## Returns

  ## Examples

  """
  @doc since: "3.5.0"
  @spec grammar(Unit.t(), Keyword.t()) :: grammar_list() | {grammar_list(), grammar_list()}

  def grammar(unit, options \\ [])

  def grammar(%Unit{} = unit, options) do
    {locale, backend} = Cldr.locale_and_backend_from(options)
    module = Module.concat(backend, :Unit)

    features =
      module.grammatical_features("root")
      |> Map.merge(module.grammatical_features(locale))

    grammatical_case = Map.fetch!(features, :case)
    plural = Map.fetch!(features, :plural)

    traverse(unit, &grammar(&1, grammatical_case, plural, options))
  end

  def grammar(unit, options) when is_binary(unit) do
    grammar(Unit.new!(1, unit), options)
  end

  defp grammar({:unit, unit}, _grammatical_case, _plural, _options) do
    {unit, {:compound, :compound}}
  end

  defp grammar({:per, {left, right}}, _grammatical_case, _plural, _options)
       when is_list(left) and is_list(right) do
    {left, right}
  end

  defp grammar({:per, {left, {right, _}}}, grammatical_case, plural, _options) when is_list(left) do
    {left, [{right, {grammatical_case.per[1], plural.per[1]}}]}
  end

  defp grammar({:per, {{left, _}, right}}, grammatical_case, plural, _options)
       when is_list(right) do
    {[{left, {grammatical_case.per[0], plural.per[0]}}], right}
  end

  defp grammar({:per, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    {[{left, {grammatical_case.per[0], plural.per[0]}}],
     [{right, {grammatical_case.per[1], plural.per[1]}}]}
  end

  defp grammar({:times, {left, right}}, _grammatical_case, _plural, _options)
       when is_list(left) and is_list(right) do
    left ++ right
  end

  defp grammar({:times, {{left, _}, right}}, grammatical_case, plural, _options)
       when is_list(right) do
    [{left, {grammatical_case.times[0], plural.times[0]}} | right]
  end

  defp grammar({:times, {left, {right, _}}}, grammatical_case, plural, _options)
       when is_list(left) do
    left ++ [{right, {grammatical_case.times[1], plural.times[1]}}]
  end

  defp grammar({:times, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    [
      {left, {grammatical_case.times[0], plural.times[0]}},
      {right, {grammatical_case.times[1], plural.times[1]}}
    ]
  end

  defp grammar({:power, {{left, _}, right}}, grammatical_case, plural, _options)
       when is_list(right) do
    [{left, {grammatical_case.power[0], plural.power[0]}} | right]
  end

  defp grammar({:power, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    [
      {left, {grammatical_case.power[0], plural.power[0]}},
      {right, {grammatical_case.power[1], plural.power[1]}}
    ]
  end

  defp grammar({:prefix, {{left, _}, {right, _}}}, grammatical_case, plural, _options) do
    [
      {left, {grammatical_case.prefix[0], plural.prefix[0]}},
      {right, {grammatical_case.prefix[1], plural.prefix[1]}}
    ]
  end

  @doc """
  Traverses a unit's decomposition and invokes
  a function on each node of the composition
  tree.

  ## Arguments

  * `unit` is any unit returned by `Cldr.Unit.new/2`

  * `fun` is any single-arity function. It will be invoked
    for each node of the composition tree. The argument is a tuple
    of the following form:

    * `{:unit, argument}`
    * `{:times, {argument_1, argument_2}}`
    * `{:prefix, {prefix_unit, argument}}`
    * `{:power, {power_unit, argument}}`
    * `{:per, {argument_1, argument_2}}`

    Where the arguments are the results returned
    from the `fun/1`.

  ## Returns

  The result returned from `fun/1`

  """
  def traverse(%Unit{base_conversion: {left, right}}, fun) when is_function(fun) do
    fun.({:per, {do_traverse(left, fun), do_traverse(right, fun)}})
  end

  def traverse(%Unit{base_conversion: conversion}, fun) when is_function(fun) do
    do_traverse(conversion, fun)
  end

  defp do_traverse([{unit, _}], fun) do
    do_traverse(unit, fun)
  end

  defp do_traverse([head | rest], fun) do
    fun.({:times, {do_traverse(head, fun), do_traverse(rest, fun)}})
  end

  defp do_traverse({unit, _}, fun) do
    do_traverse(unit, fun)
  end

  @si_prefix Cldr.Unit.Prefix.si_power_prefixes()
  @power Cldr.Unit.Prefix.power_units() |> Map.new()

  # String decomposition
  for {power, exp} <- @power do
    power_unit = String.to_atom("power#{exp}")

    defp do_traverse(unquote(power) <> "_" <> unit, fun) do
      fun.({:power, {fun.({:unit, unquote(power_unit)}), do_traverse(unit, fun)}})
    end
  end

  for {prefix, exp} <- @si_prefix do
    prefix_unit = String.to_atom("10p#{exp}" |> String.replace("-", "_"))

    defp do_traverse(unquote(prefix) <> unit, fun) do
      fun.(
        {:prefix,
         {fun.({:unit, unquote(prefix_unit)}), fun.({:unit, String.to_existing_atom(unit)})}}
      )
    end
  end

  defp do_traverse(unit, fun) when is_binary(unit) do
    fun.({:unit, String.to_existing_atom(unit)})
  end

  defp do_traverse(unit, fun) when is_atom(unit) do
    fun.({:unit, unit})
  end
end
