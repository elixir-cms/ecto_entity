defmodule EctoEntity.Type do
  @moduledoc """

  ## Examples

  Create a type, add defaults and a single field title field.

      iex> alias EctoEntity.Type
      ...> t = "posts"
      ...> |> Type.new("Post", "post", "posts")
      ...> |> Type.migration_defaults!(fn set ->
      ...>   set
      ...>   |> Type.add_field!("title", "string", "string", nullable: false)
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

  require Logger
  import Norm

  defmodule Error do
    defexception [:message]
  end

  defstruct label: nil,
            source: nil,
            singular: nil,
            plural: nil,
            fields: %{},
            changesets: %{},
            migrations: %{},
            ephemeral: %{}

  alias EctoEntity.Type

  @type field_name :: binary()
  @field_name_spec spec(is_binary())
  @type field_type :: binary() | atom()
  @field_type_spec spec(is_binary())

  # Could restrict to :create|:update|:import
  @type changeset_name :: atom()
  @changeset_name_spec one_of([:create, :update, :import])

  # Typically "cast", "validate_required" and friends
  @type changeset_op :: binary()
  @changeset_op_spec spec(
                       &(&1 in [
                           "cast",
                           "validate_required",
                           "validate_format",
                           "validate_number",
                           "validate_excluding",
                           "validate_including",
                           "validate_length"
                         ])
                     )

  @type migration_set_id :: binary()
  @migration_set_id_spec spec(is_binary())
  @type iso8601 :: binary()
  @iso8601_spec spec(is_binary())
  @default_spec spec(
                  is_binary() or is_integer() or is_float() or is_map() or
                    is_list() or
                    is_boolean()
                )

  @persistence_options_spec schema(%{
                              nullable: spec(is_boolean()),
                              indexed: spec(is_boolean()),
                              unique: spec(is_boolean()),
                              default: @default_spec
                            })
  @validation_options_spec schema(%{
                             required: spec(is_boolean()),
                             format: spec(is_boolean()),
                             number: spec(is_boolean()),
                             excluding: spec(is_boolean()),
                             including: spec(is_boolean()),
                             length: spec(is_map())
                           })
  @filter_spec coll_of(
                 schema(%{
                   type: spec(is_binary()),
                   args: spec(is_map() or is_list())
                 }),
                 kind: spec(is_list())
               )
  @meta_spec spec(is_map())

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
  @field_options_spec schema(%{
                        field_type: @field_type_spec,
                        storage_type: spec(is_binary()),
                        persistence_options: @persistence_options_spec,
                        validation_options: @validation_options_spec,
                        filters: @filter_spec,
                        meta: @meta_spec
                      })

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
  @migration_set_item_spec one_of([
                             schema(%{
                               type: spec(&(&1 == "add_primary_key")),
                               primary_type: spec(is_binary())
                             }),
                             schema(%{type: spec(&(&1 == "add_timestamps"))}),
                             schema(%{
                               type: spec(&(&1 == "add_field")),
                               identifier: spec(is_binary()),
                               field_type: @field_type_spec,
                               storage_type: spec(is_binary()),
                               persistence_options: @persistence_options_spec,
                               validation_options: @validation_options_spec,
                               filters: @filter_spec,
                               meta: @meta_spec
                             }),
                             schema(%{
                               type: spec(&(&1 == "alter_field")),
                               identifier: spec(is_binary()),
                               persistence_changes:
                                 schema(%{
                                   make_nullable: true,
                                   add_index: true,
                                   drop_index: true,
                                   remove_uniqueness: true,
                                   set_default: @default_spec
                                 }),
                               validation_options: @validation_options_spec,
                               filters: @filter_spec,
                               meta: @meta_spec
                             })
                           ])

  @type changeset :: %{
          operation: binary(),
          args: any()
        }
  @changeset_spec schema(%{
                    operation: @changeset_op_spec,
                    args: spec(is_map() or is_list())
                  })

  @type migration :: %{
          id: migration_set_id(),
          created_at: iso8601(),
          # Essentially a vector clock allowing migration code to detect conflicts
          last_migration_count: integer(),
          set: [migration_set_item(), ...]
        }
  @migration_spec schema(%{
                    id: @migration_set_id_spec,
                    created_at: @iso8601_spec,
                    last_migration_count: spec(is_integer()),
                    set: coll_of(@migration_spec, kind: spec(is_list()))
                  })

  @type t :: %Type{
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
  @type_spec schema(%{
               label: spec(is_binary()),
               source: spec(is_binary()),
               singular: spec(is_binary()),
               plural: spec(is_binary()),
               fields:
                 coll_of(
                   {@field_name_spec, @field_options_spec},
                   into: Map.new(),
                   kind: spec(is_map())
                 ),
               changesets:
                 coll_of(
                   {@changeset_name_spec, @changeset_spec},
                   into: Map.new(),
                   kind: spec(is_map())
                 ),
               migrations:
                 coll_of(
                   @migration_spec,
                   kind: spec(is_list())
                 )
             })

  @type map_t :: %{
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
          migrations: [migration()],
          ephemeral: map()
        }

  @spec new(
          source :: binary,
          label :: binary,
          singular :: binary,
          plural :: binary
        ) :: t
  def new(source, label, singular, plural)
      when is_binary(source) and is_binary(label) and is_binary(singular) and is_binary(plural) do
    %Type{
      label: label,
      source: source,
      singular: singular,
      plural: plural,
      fields: %{},
      changesets: %{},
      migrations: [],
      ephemeral: %{}
    }
  end

  @spec from_map!(type :: map_t) :: t
  def from_map!(type) do
    struct!(Type, type)
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
  def add_field!(type, identifier, field_type, storage_type, options) when is_map(type) do
    migration_set(type, fn set ->
      add_field!(set, identifier, field_type, storage_type, options)
    end)
  end

  def add_field!(migration_set, identifier, field_type, storage_type, options)
      when is_list(migration_set) do
    valid_keys = List.flatten([@persistence_options, @validation_options, [:meta, :filters]])
    check_options!(options, valid_keys)

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
    valid_keys = List.flatten([@persistence_options, @validation_options, [:meta, :filters]])
    check_options!(options, valid_keys)

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

  defp check_options!(opts, valid_keys) do
    Enum.each(opts, fn {key, _} ->
      if key not in valid_keys do
        raise Error, message: "Invalid option: #{key}"
      end
    end)
  end
end
