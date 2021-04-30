defmodule EctoEntity.Type do
  @moduledoc """

  ## Examples

  Create a type, add defaults and a single field title field.

      iex> alias EctoEntity.Type
      ...> t = "posts"
      ...> |> Type.new("Post", "post", "posts")
      ...> |> Type.migration_defaults!(fn set ->
      ...>   set
      ...>   |> Type.add_field("title", "string", "string", nullable: false)
      ...> end)
      ...> %{source: "posts", label: "Post", singular: "post", plural: "posts",
      ...>   fields: %{
      ...>     "id" => _,
      ...>     "title" => _,
      ...>     "inserted_at" => _,
      ...>     "updated_at" => _
      ...> }}
      ...> |> match?(t)
      true

  """
  @type field_name :: binary()
  @type field_type :: binary() | atom()

  # Could restrict to :create|:update|:import
  @type changeset_name :: atom()

  # Typically "cast", "validate_required" and friends
  @type changeset_op :: binary()

  @type migration_set_id :: binary()
  @type iso8601 :: binary()

  @type field_options ::
          %{
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

  @type migration_set_item ::
          %{
            # add_primary_key
            type: binary(),
            primary_type: binary()
          }
          | %{
              # add_timestamps
              type: binary()
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
          # Essentially a vector clock allowing migration code to detect conflicts
          last_migration_count: integer(),
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
            optional(field_name()) => field_options()
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
  def new(source, label, singular, plural)
      when is_binary(source) and is_binary(label) and is_binary(singular) and is_binary(plural) do
    # TODO: add guards
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

  @spec migration_defaults!(type :: t, callback :: fun()) :: t
  def migration_defaults!(%{migrations: migrations} = type, callback) do
    if migrations == [] do
      type
      |> migration_set(fn set ->
        set
        |> add_primary_key()
        |> add_timestamps()
        |> callback.()
      end)
    else
      raise "Cannot set migration defaults on a type with pre-existing migrations."
    end
  end

  @spec migration_set(type :: t, callback :: fun()) :: t
  def migration_set(%{migrations: migrations} = type, callback) do
    migration = %{
      id: new_uuid(),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      last_migration_count: Enum.count(migrations),
      set: callback.([]) |> Enum.reverse()
    }

    %{type | migrations: migrations ++ [migration]}
    |> migrations_to_fields()
    |> migrations_to_changesets()
  end

  def add_primary_key(type, use_integer \\ false)

  def add_primary_key(type, use_integer) when is_map(type) do
    migration_set(type, fn set ->
      add_primary_key(set, use_integer)
    end)
  end

  def add_primary_key(migration_set, use_integer) when is_list(migration_set) do
    primary_type =
      case use_integer do
        true -> "integer"
        false -> "uuid"
      end

    migration_set_item = %{
      type: "add_primary_key",
      primary_type: primary_type
    }

    [migration_set_item | migration_set]
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

  @persistence_options [
    :make_nullable,
    :add_index,
    :drop_index,
    :remove_uniqueness,
    :set_default
  ]

  @validation_options [
    :required,
    :format,
    :number,
    :excluding,
    :including,
    :length
  ]
  def alter_field!(type, identifier, options) when is_map(type) do
    migration_set(type, fn set ->
      alter_field!(set, type, identifier, options)
    end)
  end

  def alter_field!(migration_set, type, identifier, options) when is_list(migration_set) do
    if not migration_field_exists?(type, migration_set, identifier) do
      raise "Cannot alter a field that is not defined previously in type fields or the current migration set."
    end

    persistence_options =
      options
      |> Enum.filter(fn {key, _} ->
        key in @persistence_options
      end)
      |> Enum.into(%{})

    validation_options =
      options
      |> Enum.filter(fn {key, _} ->
        key in @validation_options
      end)
      |> Enum.into(%{})

    migration_set_item = %{
      type: "alter_field",
      identifier: identifier,
      persistence_options: persistence_options,
      validation_options: validation_options,
      filters: Keyword.get(options, :filters, []),
      meta: Keyword.get(options, :meta, %{})
    }

    [migration_set_item | migration_set]
  end

  defp migration_field_exists?(type, set, identifier) do
    Map.has_key?(type.fields, identifier) or
      Enum.any?(set, fn msi ->
        match?(%{type: "add_field", identifier: ^identifier}, msi)
      end)
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
    Map.put(fields, item.identifier, Map.drop(item, [:type, :identifier]))
  end

  defp migration_set_item_to_field(%{type: "add_timestamps"}, fields) do
    fields
    |> Map.put("inserted_at", "naive_datetime")
    |> Map.put("updated_at", "naive_datetime")
  end

  defp migration_set_item_to_field(%{type: "add_primary_key"} = item, fields) do
    ecto_type =
      case item.primary_type do
        "integer" -> "id"
        "uuid" -> "binary_id"
      end

    Map.put(fields, "id", ecto_type)
  end

  defp migration_set_item_to_field(%{type: "alter_field"} = msi, fields) do
    field = Map.get(fields, msi.identifier)

    persistence_options =
      Enum.reduce(msi.persistence_options, field.persistence_options, fn {key, value}, opts ->
        case key do
          :make_nullable -> msi_bool(opts, value, :nullable, true)
          :add_index -> msi_bool(opts, value, :indexed, true)
          :drop_index -> msi_bool(opts, value, :indexed, false)
          :remove_uniqueness -> msi_bool(opts, value, :unique, false)
          :set_default -> Map.put(opts, :default, value)
        end
      end)

    validation_options = Map.merge(field.validation_options, msi.validation_options)

    field = %{
      field
      | persistence_options: persistence_options,
        validation_options: validation_options
    }

    Map.put(fields, msi.identifier, field)
  end

  defp msi_bool(fields, apply?, key, value) do
    if apply? do
      Map.put(fields, key, value)
    else
      fields
    end
  end

  # TODO: implement
  defp migrations_to_changesets(type) do
    type
  end

  defp new_uuid do
    UUID.uuid1()
  end
end
