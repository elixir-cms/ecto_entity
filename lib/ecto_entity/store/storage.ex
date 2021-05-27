defmodule EctoEntity.Store.Storage do
  @callback get_type(settings :: map(), source :: binary()) :: EctoEntity.Type.t() | nil
  @callback put_type(settings :: map(), EctoEntity.Type.t()) :: :ok | {:error, any()}
  @callback list_types(settings :: map()) :: list(EctoEntity.Type.t())
end
