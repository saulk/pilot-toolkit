require 'quality-measure-engine'

# Stats object collects statistics regarding the content of a single section of a Patient Summary (C32 or CCR)
# As entries are added to the section, they are classified as coded vs uncoded, and within the coded as MU
# (meaningful use) coded, or alien (not the relevant code set for meaningful use clinical quality measures).
module Stats

  class CodeSetValidator

    @@ValidRegexp = {
      "SNOMED-CT" => Regexp.new("\\d+"),
      "ICD-9-CM"  => Regexp.new("^([EV])?\\d{2,3}(\\.\\d{1,2})?$"),
      "ICD-10-CM" => Regexp.new("^[A-Z]\\d{2}(\\.\\d){0,1}$"),
      "RxNorm" => Regexp.new("\\d+"),
      "CPT" => Regexp.new("^\\d{4,4}[A-Z0-9]$"),
      "LOINC" => Regexp.new("\\d+")
    }

    def self.valid_code(codeset,value)
      # make sure value is a string
      # if we can't validate, report valid
      if !@@ValidRegexp[codeset]
        return true
      else
        return (@@ValidRegexp[codeset] =~ value) == 0
      end
    end
  end

  class StatsEntry < QME::Importer::Entry

    attr_accessor :count, :codes

    def initialize
      count = 1
    end

    def count
      @count
    end

    def self.fromEntry(entry)
      sentry = Stats::StatsEntry.new
      sentry.codes = entry.codes
      sentry.description = entry.description
      sentry.count = 1
      return sentry
    end

    def add(entry)
      raise "Only entries with the same description can be added" unless entry.description == @description
      @count += entry.count
      entry.codes.each_pair do |codeset, values|
        codes[codeset] ||= []  # if it doesn't exist add it
        codes[codeset] = values.to_set.union(codes[codeset].to_set).to_a   # result is the union of codes for this codeset
      end
    end

    def dump(outfp)
      outfp.puts "StatsEntry:   description = #{@description}   count = #{@count}"
      codes.each_pair do |codeset, values|
        outfp.puts "\tcodeset #{codeset}  values #{values.join(',')}"
      end
    end

  end

  class PatientSummarySection

    attr_accessor :mu_coded_entries, :alien_coded_entries, :uncoded_entries
    attr_reader :entries, :mu_code_systems_found, :alien_code_systems_found

    def initialize(name, mu_code_systems)
      @name = name
      @entries = []
      @mu_code_systems_found = {}
      @alien_code_systems_found = {}
      @uncoded_entries = []
      @mu_coded_entries = []
      @alien_coded_entries = []
      @mu_code_systems = mu_code_systems
    end

    def merge(pss)
      @entries << pss.entries
      @mu_code_systems_found.merge(pss.mu_code_systems_found)
      @alien_code_systems_found.merge(pss.alien_code_systems_found)
      @uncoded_entries.concat(pss.uncoded_entries)
      @alien_coded_entries.concat(pss.alien_coded_entries)
      @mu_coded_entries.concat(pss.mu_coded_entries)
    end

    def unique_mu_entries
      # if there are no entries, return an empty hash
      if(mu_coded_entries.size  == 0)
        return {}
      end
      STDERR.puts "mu_coded = #{mu_coded_entries.size} "
      unique_entries = { 
        @name => { 
          "mucodesystems" => @mu_code_systems,
          "entries" => {}
        }
      }
      uhash = unique_entries[@name]["entries"]
      mu_coded_entries.each do |entry|
        sentry = Stats::StatsEntry.fromEntry(entry)
        if(uhash[sentry.description])
          uhash[sentry.description].add(sentry)
        else
          uhash[sentry.description] = sentry
        end
      end

      uhash.each_pair do | desc, entry |
        if(entry.codes.size > 0)
          uhash[desc] = 
          {
            "count" => entry.count,
            "codes" => entry.codes
          }
        else
          uhash[desc] = { "count" => entry.count }
        end
      end
      unique_entries
    end

    def unique_non_mu_entries
      # if there are no entries, return an empty hash
      if(uncoded_entries.size + alien_coded_entries.size == 0)
        return {}
      end

      unique_entries = {
        @name => {
          "mucodesystems" => @mu_code_systems,
          "entries" => {}
        }
      }
      uhash = unique_entries[@name]["entries"]

      uncoded_entries.each do |entry|
        sentry = Stats::StatsEntry.fromEntry(entry)
        if(uhash[sentry.description])
          uhash[sentry.description].add(sentry)
        else
          uhash[sentry.description] = sentry
        end
      end

      alien_coded_entries.each do |entry|
        sentry = Stats::StatsEntry.fromEntry(entry)
        if(uhash[sentry.description])
          uhash[sentry.description].add(sentry)
        else
          uhash[sentry.description] = sentry
        end
      end

      uhash.each_pair do |desc, entry|
        if(entry.codes.size > 0)
          uhash[desc] = {"count" => entry.count, "codes" => entry.codes }
        else
          uhash[desc] = {"count" => entry.count}
        end
      end
      unique_entries
    end

    def summary
      results = { 
        @name => {
          "entries" =>                     num_coded_entries + num_uncoded_entries,
          "mu code systems" =>             @mu_code_systems,
          "coded entries" =>               num_coded_entries,
          "mu coded entries" =>            num_mu_coded_entries,
          "mu code systems in use" =>      mu_code_systems_found,
          "non-mu coded entries" =>        num_alien_coded_entries,
          "non-mu code systems in use" =>  alien_code_systems_found
        }
      }
    end

    def dump(outfp)
      outfp.puts "Section #{@name}:   mu_code_systems = #{@mu_code_systems.join(',')}"
      outfp.puts "\tEntries: #{num_coded_entries + num_uncoded_entries}, #{num_coded_entries} coded"
      if (num_alien_coded_entries > 0)
        outfp.puts "\taliens: #{num_alien_coded_entries} #{alien_code_systems_found}"
      end
      if (num_mu_coded_entries > 0)
        andaliens = ""
        if (alien_code_systems_found.size > 0)
          andaliens = "and #{alien_code_systems_found}"
        end
        outfp.puts "\tmu:     #{num_mu_coded_entries}   #{mu_code_systems_found} #{andaliens}"  
      end
    end

    def num_uncoded_entries
      uncoded_entries.size
    end

    def num_mu_coded_entries 
      mu_coded_entries.size
    end

    def num_alien_coded_entries
      alien_coded_entries.size
    end

    def num_coded_entries
      mu_coded_entries.size + alien_coded_entries.size
    end

=begin
def alien_code_systems_found
@alien_code_systems_found.keys
end

def mu_code_systems_found
@mu_code_systems_found.keys
end
=end
def add_entry(entry)
  mu_code_found = false
  valid_code_found = false
  @entries << entry
  entry.codes.each_pair do |codeset, values|
    valid_code = false
    values.each do | value |   # Is there a valid code for this codeset
      #v = (Stats::CodeSetValidator.valid_code(codeset, value) && entry.usable?)
      v = (Stats::CodeSetValidator.valid_code(codeset, value) )
      valid_code = valid_code || v
    end
    # Timestamp code breaks CCR test cases, since we don't yet capture timestamps there
    # if(!valid_code || !entry.usable?)   #If we've not seen a valid code or there is a timestamp
    if(!valid_code)
      STDERR.puts "Entry is not usable due to invalid code or lack of timestamp"
    else #otherwise, is it an appropriate code set?
      valid_code_found = true
      if @mu_code_systems.include?(codeset)
        mu_code_found = true;
        @mu_code_systems_found[codeset] = true
      else
        @alien_code_systems_found[codeset] = true
      end
    end
  end 
  if !valid_code_found
    @uncoded_entries << entry
  else
    if mu_code_found
      @mu_coded_entries << entry    # If an entry has both mu codes and alien codes, it is classified as mu_coded
    else
      @alien_coded_entries << entry # contains only non-mu codes
    end
  end
end
end
end

# if launched as a standalone program, not loaded as a module
if __FILE__ == $0

  section = Stats::PatientSummarySection.new("junk",["ICD9","ICD10","SNOMED-CT"])

  entry = QME::Importer::Entry.new
  entry.description = "test_entry 1"
  entry.add_code(32000, "ICD9")
  entry.add_code(32001,"ICD9")
  entry.add_code(32000, "LOINC")
  entry.add_code(32001,"ICD10")
  entry.add_code(1,"GORK")
  section.add_entry(entry)

  entry1 = QME::Importer::Entry.new
  entry1.description = "test_entry 2"
  entry1.add_code(32000, "ICD9")
  entry1.add_code(32002,"ICD9")
  entry1.add_code(32000, "FOO1")
  entry1.add_code(32001,"BAR1")
  section.add_entry(entry)

  entry2 = QME::Importer::Entry.new
  entry2.description = "test_entry 3"
  entry2.add_code(32000, "FOO")
  entry2.add_code(32002,"FOO")
  entry2.add_code(32000, "BAR")
  entry2.add_code(32001,"BAR1")
  section.add_entry(entry2)

  entry3 = QME::Importer::Entry.new
  entry3.description = "test_entry 4"
  entry3.add_code(32002, "FOO")
  entry3.add_code(32004,"FOO")
  entry3.add_code(32006, "BAR")
  entry3.add_code(32008,"BAR1")
  section.add_entry(entry3)

  unique_non_mu_entries = section.unique_non_mu_entries
  unique_non_mu_entries.each_pair do | key, value |
    STDERR.puts "key = #{key}   value = #{value}   valueclass = #{value.class}"
    value.each_pair do | k,v|
      STDERR.puts "\tkey = #{k}   value = #{v}   valueclass = #{v.class}"
    end
  end

  section.dump(STDERR)
  STDERR.puts section.summary
  STDERR.puts JSON.pretty_generate(section.unique_non_mu_entries)
  entrya = Stats::StatsEntry.fromEntry(entry)
  entry1a = Stats::StatsEntry.fromEntry(entry1)
  entry1a.description = entrya.description

  entrya.add(entry1a)
  entrya.dump(STDERR)

end