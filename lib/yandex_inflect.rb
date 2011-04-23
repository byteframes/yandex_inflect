# -*- encoding: utf-8 -*- 

$KCODE = 'u'

$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'rubygems'
require 'httparty'
require 'i18n'

module YandexInflect
  # Число доступных вариантов склонений
  INFLECTIONS_COUNT = 6
  
  # Класс для получения данных с веб-сервиса Яндекса.
  class Inflection
    include HTTParty
    base_uri 'http://export.yandex.ru/'

    # Получить склонения для имени <tt>name</tt>
    def get(name)
      options = {}
      options[:query] = { :name => name }
      inflections = self.class.get("/inflect.xml", options)
      
      return inflections["inflections"]["inflection"]
    end
  end
  
  # Кеширование успешных результатов запроса к веб-сервису
  @@cache = {}
  
  # Возвращает массив склонений (размером <tt>INFLECTIONS_COUNT</tt>) для слова <tt>word</tt>.
  #
  # Если слово не найдено в словаре, будет возвращен массив размерностью <tt>INFLECTIONS_COUNT</tt>,
  # заполненный этим словом.
  def self.inflections(word)
    inflections = []
    
    lookup = cache_lookup(word) 
    return lookup if lookup
    
    get = Inflection.new.get(word) rescue nil # если поднято исключение, переходим к третьему варианту и не кешируем
    case get
      when Array then 
        # Яндекс вернул массив склонений
        inflections = get
        # Кладем в кеш
        cache_store(word, inflections)
      when String then 
        # Яндекс вернул не массив склонений (слово не найдено в словаре),
        # а только строку, забиваем этой строкой весь массив 
        inflections.fill(get, 0..INFLECTIONS_COUNT-1)
        # Кладем в кеш
        cache_store(word, inflections)
      else
        # Забиваем варианты склонений оригиналом
        inflections.fill(word, 0..INFLECTIONS_COUNT-1)
    end
 
    inflections
  end
  
  # Очистить кеш
  def self.clear_cache
    @@cache.clear
  end
  
  private
    def self.cache_lookup(word)
      @@cache[word.to_s]
    end
  
    def self.cache_store(word, value)
      @@cache[word.to_s] = value
    end
end

######
# I18n.i('хуй', 'рд')
# i('хуй', 'рд')

if I18n.locale == :ru
  defined?(Inflection) or raise 'You should run "rails g yandex_inflect" (or "script/generate yandex_inflect") and rake db:migrate before using this version of yandex_inflect'
  YandexInflect.instance_eval do
    self::CASES = %w{им ро да ви тв пр}
    
    def store_inflections(word, inflections)
      inflections = ActiveSupport::JSON.encode(inflections)
      Inflection.create!(:original_word => word, :inflected_variants => inflections)
    end
    
    def get_stored_inflections(word, no_cache = false)
      inflections = []
      
      unless no_cache
        result = cache_lookup(word)
        return result if result
      end
      
      result = Inflection.find_by_original_word(word)
      unless result.nil?
        inflections = ActiveSupport::JSON.decode(result.inflected_variants)
      else
        inflections = inflections(word)
        store_inflections(word, inflections)
      end
      
      inflections
    end
  end
  
  I18n.instance_eval do
    def inflect(word, kase)
      kase = YandexInflect::CASES.include?(kase) ? YandexInflect::CASES.find_index(kase) : 0
      inflections = YandexInflect.get_stored_inflections(word)
      return inflections[kase]
    end
  end
  
  if defined?(ActionController::Translation) 
    ActionController::Translation.instance_eval do
      def inflect(*args)
        I18n.inflect(*args)
      end
      
      alias :i :inflect
    end
  end
else
  YandexInflect.instance_eval do
    def no_locale
      raise 'You should have russian locale yo use this version of yandex_inflect'
    end
    
    alias :store_inflections :no_locale
    alias :get_stored_inflections :no_locale
  end
end