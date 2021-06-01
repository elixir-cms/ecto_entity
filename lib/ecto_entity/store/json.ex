defmodule EctoEntity.Store.SimpleJson do
  @behaviour EctoEntity.Store.Storage
  import EctoEntity.Store.Storage, only: [error: 2]
  require Logger

  alias EctoEntity.Type

  @assorted_file_errors [
    :eacces,
    :eisdir,
    :enotdir,
    :enomem
  ]

  @impl true
  def get_type(%{directory_path: path}, source) do
    File.mkdir_p!(path)

    filepath = Path.join(path, "#{source}.json")

    with {:ok, json} <- File.read(filepath),
         {:ok, decoded} <- Jason.decode(json),
         {:ok, type} <- Type.from_persistable(decoded) do
      {:ok, type}
    else
      {:error, :enoent} ->
        {:error, error(:not_found, "File not found")}

      {:error, err} when err in @assorted_file_errors ->
        {:error, ferror(err)}

      {:error, %Jason.DecodeError{} = err} ->
        Logger.error("JSON Decoding error: #{inspect(err)}", error: err)
        {:error, error(:decoding_failed, "JSON decoding failed.")}

      {:error, :bad_type} ->
        {:error, error(:normalize_definition_failed, "Failed to normalize definition.")}

      {:error, _} ->
        {:error, error(:unknown, "Unknown error")}
    end
  end

  @impl true
  def put_type(%{directory_path: path}, definition) do
    try do
      File.mkdir_p!(path)

      data =
        definition
        |> Type.to_persistable()
        |> Jason.encode!()

      path
      |> Path.join("#{definition.source}.json")
      |> File.write!(data)
    catch
      _ -> {:error, :unknown}
    end

    :ok
  end

  @impl true
  def list_types(%{directory_path: path}) do
    File.mkdir_p!(path)

    File.ls!(path)
    |> Enum.filter(fn filename ->
      String.ends_with?(filename, ".json")
    end)
    |> Enum.map(fn filename ->
      Path.basename(filename, ".json")
    end)
  end

  defp ferror(err) do
    Storage.error(:reading_failed, "File reading error: #{inspect(:file.format_error(err))}")
  end
end
