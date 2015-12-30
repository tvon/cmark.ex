defmodule Cmark do
  @moduledoc """
  Compiles Markdown formatted text into HTML

  Provides:

  * `to_html/1`
  * `to_html/2`
  * `to_html/3`
  * `to_html_each/3`
  * `to_latex/1`
  * `to_latex/2`
  * `to_latex/3`
  * `to_latex_each/3`

  """

  @formats [:html, :xml, :man, :commonmark, :latex]

  @doc """
  Compiles one or more (list) Markdown documents to HTML and returns result.

  ## Examples

      iex> "test" |> Cmark.to_html
      "<p>test</p>\\n"

      iex> ["# also works", "* with list", "`of documents`"] |> Cmark.to_html
      ["<h1>also works</h1>\\n",
      "<ul>\\n<li>with list</li>\\n</ul>\\n",
      "<p><code>of documents</code></p>\\n"]

  """

  @formats |> Enum.each fn format ->
    def unquote(:"to_#{format}")(data) when is_list(data) do
      parse_doc_list(data, [:default], unquote(format))
    end

    def unquote(:"to_#{format}")(data) when is_bitstring(data) do
      parse_doc(data, [:default], unquote(format))
    end
  end


  @doc """
  Compiles one or more (list) Markdown documents to HTML using provided options
  and returns result.

  Options are paseed as a list of atoms.  Available options are:

  * `:sourcepos` - Include a `data-sourcepos` attribute on all block elements.
  * `:softbreak` - Render `softbreak` elements as hard line breaks.
  * `:normalize` - Normalize tree by consolidating adjacent text nodes.
  * `:smart` - Convert straight quotes to curly, --- to em dashes, -- to en dashes.
  * `:validate_utf8` - Validate UTF-8 in the input before parsing, replacing
  illegal sequences with the replacement character U+FFFD.
  * `:safe` - Suppress raw HTML and unsafe links (`javascript:`, `vbscript:`,
  `file:`, and `data:`, except for `image/png`, `image/gif`, `image/jpeg`, or
  `image/webp` mime types).  Raw HTML is replaced by a placeholder HTML
  comment. Unsafe links are replaced by empty strings.


  ## Examples

  iex> Cmark.to_html(~s(Use option to enable "smart" quotes.), [:smart])
  "<p>Use option to enable “smart” quotes.</p>\\n"

  """

  @formats |> Enum.each fn format ->
    def unquote(:"to_#{format}")(data, options) when is_list(data) and is_list(options) do
      parse_doc_list(data, options, unquote(format))
    end

    def unquote(:"to_#{format}")(data, options) when is_bitstring(data) and is_list(options) do
      parse_doc(data, options, unquote(format))
    end
  end


  @doc """
  Compiles one or more (list) Markdown documents to HTML and calls function with result.

  ## Examples

  iex> callback = fn (html) -> "HTML is \#{html}" |> String.strip end
  iex> "test" |> Cmark.to_html(callback)
  "HTML is <p>test</p>"

  iex> callback = fn (htmls) ->
  iex>   Enum.map(htmls, &String.strip/1) |> Enum.join("<hr>")
  iex> end
  iex> ["list", "test"] |> Cmark.to_html(callback)
  "<p>list</p><hr><p>test</p>"

  """

  @formats |> Enum.each fn format ->
    def unquote(:"to_#{format}")(data, callback) when is_list(data) and is_function(callback) do
      parse_doc_list(data, callback, [:default], unquote(format))
    end

    def unquote(:"to_#{format}")(data, callback) when is_bitstring(data) and is_function(callback) do
      parse_doc(data, callback, [:default], unquote(format))
    end
  end


  @doc """
  Compiles one or more (list) Markdown documents to HTML using provided options
  and calls function with result.

  ## Examples

  iex> callback = fn (htmls) ->
  iex>   Enum.map(htmls, &String.strip/1) |> Enum.join("<hr>")
  iex> end
  iex> ["en-dash --", "ellipsis..."] |> Cmark.to_html(callback, [:smart])
  "<p>en-dash –</p><hr><p>ellipsis…</p>"
  """

  @formats |> Enum.each fn format ->
    def unquote(:"to_#{format}")(data, callback, options) when is_list(data) and is_list(options) do
      parse_doc_list(data, callback, options, unquote(format))
    end

    def unquote(:"to_#{format}")(data, callback, options) when is_bitstring(data) and is_list(options) do
      parse_doc(data, callback, options, unquote(format))
    end
  end

  @doc """
  Compiles a list of Markdown documents using provided options and calls
  function for each item.

  ## Examples

  iex> callback = fn (html) -> "HTML is \#{html |> String.strip}" end
  iex> ["list", "test"] |> Cmark.to_html_each(callback)
  ["HTML is <p>list</p>", "HTML is <p>test</p>"]

  """

  @formats |> Enum.each fn format ->
    def unquote(:"to_#{format}_each")(data, callback, options \\ [:default]) when is_list(data) do
      parse_doc_list_each(data, callback, options, unquote(format))
    end
  end


  defp parse_doc_list(documents, options, format) do
    documents
    |> Enum.map(&Task.async(fn -> parse_doc(&1, options, format) end))
    |> Enum.map(&Task.await(&1))
  end

  defp parse_doc_list(documents, callback, options, format) do
    callback.(parse_doc_list(documents, options, format))
  end

  defp parse_doc_list_each(documents, callback, options, format) do
    documents
    |> Enum.map(&Task.async(fn -> parse_doc(&1, callback, options, format) end))
    |> Enum.map(&Task.await(&1))
  end

  defp parse_doc(document, options, format) do
    to_cmark_nif(document, options, format)
  end

  defp parse_doc(document, callback, options, format) do
    callback.(to_cmark_nif(document, options, format))
  end

  defp to_cmark_nif(data, options \\ [:default], format \\ :html) do
    Cmark.Nif.render(data, parse_options(options), parse_format(format))
  end

  defp parse_options(options) do
    use Bitwise

    flags = %{
      default: 0,
      sourcepos: 1,
      hardbreaks: 2,
      normalize: 4,
      smart: 8,
      validate_utf8: 16,
      safe: 32
    }

    Enum.reduce(options, 0, fn(x, acc) -> flags[x] ||| acc end)
  end


  defp parse_format(format) do
    %{
      none: 0,
      html: 1,
      xml: 2,
      man: 3,
      commonmark: 4,
      latex: 5
    }[format]
  end
end
