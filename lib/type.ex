defmodule EctoEntity.Type do
  @type field_name :: binary()
  @type field_type :: binary() | atom()

  # Could restrict to :create|:update|:import
  @type changeset_name :: atom()

  # Typically "cast", "validate_required" and friends
  @type changeset_op :: binary()

  @type migration_set_id :: binary()
  @type iso8601 :: binary()

  @type migration_set_item ::
          %{
            # add_primary_key
            type: binary(),
            identifier: binary(),
            key_type: binary()
          }
          | %{
              # add_field
              type: binary(),
              identifier: binary(),
              field_type: field_type(),
              storage_type: binary(),
              # Options enforced at the persistence layer, typically DB options
              persistence_options: %{
                required(:nullable) => bool(),
                required(:indexed) => bool(),
                optional(:unique) => bool(),
                optional(:default) => any()
              },
              # Options enforced at the validation step, equivalently to Ecto.Changeset
              validation_options: %{
                required(:required) => bool(),
                optional(:format) => binary(),
                optional(:number) => %{optional(binary()) => number()},
                optional(:excluding) => any(),
                optional(:including) => any(),
                optional(:length) => %{optional(binary()) => number()}
              },
              # Filters, such as slugify and other potential transformation for the incoming data
              filters: [
                %{
                  type: binary(),
                  args: any()
                },
                ...
              ],
              # For presentation layer metadata and such
              meta: %{
                optional(binary()) => any()
              }
            }
          | %{
              # alter_field
              required(:type) => binary(),
              required(:identifier) => binary(),
              # Options enforced at the persistence layer, typically DB options
              optional(:persistence_changes) => %{
                optional(:make_nullable) => true,
                optional(:add_index) => true,
                optional(:drop_index) => true,
                optional(:remove_uniqueness) => true,
                optional(:set_default) => any()
              },
              # Options enforced at the validation step, equivalently to Ecto.Changeset
              optional(:validation_options) => %{
                optional(:required) => bool(),
                optional(:format) => binary(),
                optional(:number) => %{optional(binary()) => number()},
                optional(:excluding) => any(),
                optional(:including) => any(),
                optional(:length) => %{optional(binary()) => number()}
              },
              # Filters, such as slugify and other potential transformation for the incoming data
              optional(:filters) => [
                %{
                  type: binary(),
                  args: any()
                },
                ...
              ],
              # For presentation layer metadata and such
              optional(:meta) => %{
                optional(binary()) => any()
              }
            }

  @type changeset :: %{
          operation: binary(),
          args: any()
        }

  @type migration :: %{
          id: migration_set_id(),
          created_at: iso8601(),
          set: [migration_set_item(), ...]
        }

  @type t :: %{
          # pretty name
          label: binary(),
          # slug, often used for table-name
          source: binary(),
          singular: binary(),
          plural: binary(),
          fields: %{
            optional(field_name()) => field_type()
          },
          changesets: %{
            optional(changeset_name()) => [changeset()]
          },
          migrations: [migration()]
        }

  @spec new(
          source :: binary,
          label :: binary,
          singular :: binary,
          plural :: binary
        ) :: t
  def new(source, label, singular, plural) do
    %{
      label: label,
      source: source,
      singular: singular,
      plural: plural,
      fields: %{},
      changesets: %{},
      migrations: []
    }
  end

  @spec migration_set(type :: t, callback :: fun()) :: t
  def migration_defaults!(%{migrations: migrations} = type, callback) do
    if migrations == [] do
    else
      raise "Cannot set migration defaults on a type with pre-existing migrations."
    end
  end

  @spec migration_set(type :: t, callback :: fun()) :: t
  def migration_set(%{migrations: migrations} = type, callback) do
    migration = %{
      id: new_uuid(),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      set: callback.([]) |> Enum.reverse()
    }

    %{type | migrations: migrations ++ [migration]}
    |> migrations_to_fields()
    |> migrations_to_changesets()
  end

  @persistence_options [
    :nullable,
    :indexed,
    :unique,
    :default
  ]

  @validation_options [
    :required,
    :format,
    :number,
    :excluding,
    :including,
    :length
  ]
  def add_field(type, identifier, field_type, storage_type, options) when is_map(type) do
    migration_set(type, fn set ->
      add_field(set, identifier, field_type, storage_type, options)
    end)
  end

  def add_field(migration_set, identifier, field_type, storage_type, options)
      when is_list(migration_set) do
    persistence_options =
      options
      |> Enum.filter(fn {key, _} ->
        key in @persistence_options
      end)
      |> Enum.into(%{})
      |> Map.put_new(:nullable, true)
      |> Map.put_new(:indexed, false)

    validation_options =
      options
      |> Enum.filter(fn {key, _} ->
        key in @validation_options
      end)
      |> Enum.into(%{})
      |> Map.put_new(:required, false)

    migration_set_item = %{
      type: "add_field",
      identifier: identifier,
      field_type: field_type,
      storage_type: storage_type,
      persistence_options: persistence_options,
      validation_options: validation_options,
      filters: Keyword.get(options, :filters, []),
      meta: Keyword.get(options, :meta, %{})
    }

    [migration_set_item | migration_set]
  end

  def add_timestamps(type) when is_map(type) do
    migration_set(type, fn set ->
      add_timestamps(set)
    end)
  end

  def add_timestamps(migration_set) when is_list(migration_set) do
    migration_set_item = %{
      type: "add_timestamps"
    }

    [migration_set_item | migration_set]
  end

  defp migrations_to_fields(type) do
    fields =
      Enum.reduce(type.migrations, %{}, fn migration, fields ->
        # msi - migration_set_item
        Enum.reduce(migration.set, fields, &migration_set_item_to_field/2)
      end)

    %{type | fields: fields}
  end

  defp migration_set_item_to_field(%{type: "add_field"} = item, fields) do
    Map.put(fields, item.identifier, item.field_type)
  end

  defp migration_set_item_to_field(%{type: "add_timestamps"}, fields) do
    fields
    |> Map.put("inserted_at", "naive_datetime")
    |> Map.put("updated_at", "naive_datetime")
  end

  # TODO: implement
  defp migrations_to_changesets(type) do
    type
  end

  # TODO: it lies!
  defp new_uuid do
    [:positive, :monotonic]
    |> System.unique_integer()
    |> Integer.to_string()
  end
end
