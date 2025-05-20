defmodule TCPFilter.Builder do
  defmacro __using__(_opts) do
    quote do
      @behaviour TCPFilter.Filter

      def filter(control_message, message) do
        filter_builder_filter(control_message, message)
      end

      def filter(control_message) do
        filter_builder_filter(control_message)
      end

      import TCPFilter.Builder, only: [filter: 1]

      Module.register_attribute(__MODULE__, :filters, accumulate: true)
      @before_compile TCPFilter.Builder
    end
  end

  defmacro __before_compile__(env) do
    filters = Module.get_attribute(env.module, :filters)

    {filter1, filter2} = TCPFilter.Builder.compile(filters)

    quote do
      defp filter_builder_filter(control_message) do
        unquote(filter1)
      end
      defp filter_builder_filter(control_message, message) do
        unquote(filter2)
      end
    end
  end

  def compile(pipeline) do
    Enum.reduce(pipeline, {:ignore, :ignore}, fn filter, {acc1, acc2} ->
      {
        if function_exported?(filter, :filter, 1) do
          quote do
            case unquote(filter).filter(control_message) do
              :ignore ->
                unquote(acc1)
              :ok ->
                case unquote(acc1) do
                  :ignore ->
                    :ok
                  other ->
                    other
                end
              other ->
                other
            end
          end
        else
          raise ArgumentError, "#{inspect(filter)} must implement filter/2"
        end,

        if function_exported?(filter, :filter, 2) do
          quote do
            case unquote(filter).filter(control_message, message) do
              :ignore ->
                unquote(acc2)
              :ok ->
                case unquote(acc2) do
                  :ignore ->
                    :ok
                  other ->
                    other
                end
              other ->
                other
            end
          end
        else
          raise ArgumentError, "#{inspect(filter)} must implement filter/2"
        end
      }
    end)
  end

  defmacro filter(filter) do
    quote do
      @filters unquote(filter)
    end
  end
end
