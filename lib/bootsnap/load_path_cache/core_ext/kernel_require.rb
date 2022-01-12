# frozen_string_literal: true
module Bootsnap
  module LoadPathCache
    module CoreExt
      def self.make_load_error(path)
        err = LoadError.new(+"cannot load such file -- #{path}")
        err.instance_variable_set(Bootsnap::LoadPathCache::ERROR_TAG_IVAR, true)
        err.define_singleton_method(:path) { path }
        err
      end

      module Kernel
        # Note that require registers to $LOADED_FEATURES while load does not.
        def require(path)
          return false if Bootsnap::LoadPathCache.loaded_features_index.key?(path)

          if (resolved = Bootsnap::LoadPathCache.load_path_cache.find(path))
            Bootsnap::LoadPathCache.loaded_features_index.register(path, resolved) do
              return super(resolved || path)
            end
          end

          raise(Bootsnap::LoadPathCache::CoreExt.make_load_error(path))
        rescue LoadError => e
          e.instance_variable_set(Bootsnap::LoadPathCache::ERROR_TAG_IVAR, true)
          raise(e)
        rescue Bootsnap::LoadPathCache::ReturnFalse
          false
        rescue Bootsnap::LoadPathCache::FallbackScan
          Bootsnap::LoadPathCache.loaded_features_index.register(path, nil) do
            super(path)
          end
        end

        def require_relative(path)
          location = caller_locations(1..1).first
          realpath = Bootsnap::LoadPathCache.realpath_cache.call(
            location.absolute_path || location.path, path
          )
          require(realpath)
        end

        def load(path, wrap = false)
          if (resolved = Bootsnap::LoadPathCache.load_path_cache.find(path, try_extensions: false))
            super(resolved, wrap)
          else
            super(path, wrap)
          end
        end
      end

      module Module
        def autoload(const, path)
          # NOTE: This may defeat LoadedFeaturesIndex, but it's not immediately
          # obvious how to make it work. This feels like a pretty niche case, unclear
          # if it will ever burn anyone.
          #
          # The challenge is that we don't control the point at which the entry gets
          # added to $LOADED_FEATURES and won't be able to hook that modification
          # since it's done in C-land.
          super(const, Bootsnap::LoadPathCache.load_path_cache.find(path) || path)
        rescue LoadError => e
          e.instance_variable_set(Bootsnap::LoadPathCache::ERROR_TAG_IVAR, true)
          raise(e)
        rescue Bootsnap::LoadPathCache::ReturnFalse
          false
        rescue Bootsnap::LoadPathCache::FallbackScan
          super(const, path)
        end
      end
    end

    ::Kernel.prepend(CoreExt::Kernel)
    ::Kernel.singleton_class.prepend(CoreExt::Kernel)
    ::Module.prepend(CoreExt::Module)
  end
end
