require "#{File.dirname(__FILE__)}/object"
require 'rubygems'
require 'metaid'

class Functor
  
  def self.cache_config(options={})
    (@cache_config ||= { :size => 10_000, :base => 10 }).merge!(options)
  end
  
  module Method
    
    def self.included( k )
      
      def k.functor_cache; @functor_cache ||= [{},{},{},{}]; end
      
      def k.functor_cache_config(options={})
        (@functor_cache_config ||= Functor.cache_config).merge!(options)
      end
      
      def k.functor( name, *pattern, &action )
        _functor( name, false, *pattern, &action)
      end
      
      def k.functor_with_self( name, *pattern, &action )
        _functor( name, true, *pattern, &action)
      end
      
      def k.method_missing(name, *args)
        if args.empty? && name.to_s =~ /^_/
          lambda { true }
        else
          super
        end
      end
      
      private
      
      def k._functor( name, with_self=false, *pattern, &action)
        name = name.to_s
        c0,c1,c2,c3 = (0..3).map { |i| functor_cache[i][name] ||= {} }
        cache_size, cache_base = functor_cache_config[:size], functor_cache_config[:base]
        c1_thresh,c2_thresh,c3_thresh = cache_base.to_i, (cache_base ** 2).to_i, (cache_base ** 3).to_i
        # Grab the current incarnation of The Method
        old = instance_method(name) if instance_methods.include?( name )           
        define_method( name, action )
        # Grab the newly redefined version of The Method
        newest = instance_method(name)
        
        # Recursively redefine The Method using the newest and previous incarnations
        define_method( name ) do | *args |
          match_args = with_self ? [self] + args : args
          signature = match_args.hash
          # chech caches in order of priority.  Inlined ugliness makes for speed
          if meth = c3[signature]
            meth[0].bind(self).call(*args)
          elsif meth = c2[signature]
            # when c3 fills up, shift its contents down to c2, and so forth
            c0, c1, c2, c3 = c1, c2, c3, {} if cache_size && c3.size >= cache_size
            # methods are cached as [ method, counter ]
            c3[signature] = c2.delete(signature) if meth[-1] > c3_thresh
            meth[-1] += 1
            meth[0].bind(self).call(*args)
          elsif meth = c1[signature]
            c0, c1, c2 = c1, c2, {} if cache_size && c2.size >= cache_size
            c2[signature] = c1.delete(signature) if meth[-1] > c2_thresh
            meth[-1] += 1
            meth[0].bind(self).call(*args)
          elsif meth = c0[signature]
            c0, c1 = c1, {} if cache_size && c1.size >= cache_size
            c1[signature] = c0.delete(signature) if meth[-1] > c1_thresh 
            meth[-1] += 1
            meth[0].bind(self).call(*args)
          # On cache miss, call the newest incarnation if we match the topmost pattern
          elsif Functor.match?(match_args, pattern)
            c0 = {} if cache_size && c0.size >= cache_size
            c0[signature] = [newest, 0]
            newest.bind(self).call(*args)
          # or call the previous incarnation of The Method
          elsif old
            old.bind(self).call(*args)
          # and if there are no older incarnations, whine about it
          else
            raise ArgumentError.new( "No functor matches the given arguments for method :#{name}." )
          end
        end 
      end
      
    end
  end
  
  # Stuff for using standalone instances of Functor
  
  # When creating a functor instance, use given within the block to add actions
  def initialize( &block )
    yield( self ) if block_given?
  end
  
  def given( *pattern, &action )
    name = "call"
    old = method(name) if methods.include?( name )
    class << self; self; end.instance_eval do
      define_method( name, action )
    end
    newest = method(name)
    class << self; self; end.instance_eval do
      
      define_method( name ) do | *args |
        if Functor.match?(args, pattern)
          newest.call(*args)
        elsif old
          old.call(*args)
        else
          raise ArgumentError.new( "No functor matches the given arguments for method :#{name}." )
        end
      end
      
    end
  end
  
  def []( *args, &block )
    call( *args, &block )
  end
  
  def to_proc ; lambda { |*args| self.call( *args ) } ; end
    
  def self.match?( args, pattern )
    args.all? do |a|
      p = pattern[args.index(a)]; p === a || ( p.respond_to?(:call) && p.call(a))
    end if args.length == pattern.length
  end
    
end