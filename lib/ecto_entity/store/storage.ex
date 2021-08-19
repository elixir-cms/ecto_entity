defmodule EctoEntity.Store.Storage do
  defmodule Error do
    defexception [:type, :message]

    @type t :: %__MODULE__{
            type:
              :not_found
              | :reading_failed
              | :decoding_failed
              | :normalize_definition_failed
              | :unknown,
            message: binary()
          }
  end

  @spec error(
          type ::
            :not_found
            | :reading_failed
            | :decoding_failed
            | :normalize_definition_failed
            | :unknown,
          message :: binary()
        ) :: Error.t()
  def error(type, message) do
    %Error{type: type, message: message}
  end

  @callback get_type(settings :: map(), source :: binary()) :: EctoEntity.Type.t() | nil
  @callback put_type(settings :: map(), EctoEntity.Type.t()) :: :ok | {:error, any()}
  @callback remove_type(settings :: map(), source :: binary()) :: :ok | {:error, any()}
  @callback list_types(settings :: map()) :: list(EctoEntity.Type.t())
end
