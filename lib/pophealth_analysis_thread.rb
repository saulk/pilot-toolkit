import "java.lang.Thread"
import "javax.swing.JOptionPane"

require_relative 'pophealth_import_file'

class PophealthAnalysisThread < Thread

  def initialize
    @c32_schematron_validator = Validation::ValidatorRegistry.c32_schematron_validator
    @c32_schema_validator =     Validation::ValidatorRegistry.c32_schema_validator
    @ccr_schema_validator =     Validation::ValidatorRegistry.ccr_schema_validator
  end

  def set_parent_jframe(parent_jframe)
    @pophealth_jframe = parent_jframe
  end

  def set_import_directory(import_directory)
    @import_directory = import_directory
  end

  def run
    files = @import_directory.listFiles()
    xmlfiles = []
    files.each do |file|
      if PophealthImportFile.new(file).is_valid_format 
        xmlfiles << file
      end
    end
    if (xmlfiles && (xmlfiles.size > 0))
      analyze_data(xmlfiles)
    else
      JOptionPane.showMessageDialog(@pophealth_jframe,
        "Directory selected '" + @import_directory.to_s +
          " does not have any files in it.\nPlease select a directory " +
          "with either your patient C32 or CCR Continuity of Care XML records",
        "popHealth: Invalid Data Input Directory Selection",
        JOptionPane::WARNING_MESSAGE)
    end
  end

  private

  def analyze_data(files)
    analysis_results = prime_analysis_results
    file_counter = 0
    file_validation_errors = 0
    # iterate over the files in the selected directory
    files.each do |next_file|
      puts "Considering " + next_file.to_s
      continuity_of_care_record = File.read(next_file.get_path)
      if (PophealthImporterListener.continuity_of_care_mode == :c32_mode)
        c32_schema_errors = @c32_schema_validator.validate(continuity_of_care_record)
        c32_schematron_errors = @c32_schematron_validator.validate(continuity_of_care_record)
        if (c32_schema_errors.size > 0 || c32_schematron_errors.size > 0)
          file_validation_errors += 1
        end
        doc = Nokogiri::XML(continuity_of_care_record)
        doc.root.add_namespace_definition('cda', 'urn:hl7-org:v3')
        patient_summary_report = Stats::PatientSummaryReport.from_c32(doc)
        update_analysis_results(patient_summary_report, analysis_results)
      else
        if @ccr_schema_validator && @ccr_schema_validator.validate(continuity_of_care_record).size() > 0
          file_validation_errors += 1
        end
        doc = Nokogiri::XML(continuity_of_care_record)
        doc.root.add_namespace_definition('ccr', 'urn:astm-org:CCR')
        patient_summary_report = Stats::PatientSummaryReport.from_ccr(doc)
        update_analysis_results(patient_summary_report, analysis_results)
      end
      file_counter += 1
      @pophealth_jframe.set_analysis_progress_bar((file_counter.to_f) / (files.size.to_f))
      @pophealth_jframe.get_content_pane.repaint()
    end
    analysis_results["number_files"] = files.size
    # if running in CCR mode, and the user has not setup a CCR schema file, send message to the
    # display that they need to buy the CCR schema file and configure the importer
    if (PophealthImporterListener.continuity_of_care_mode == :ccr_mode && !@ccr_schema_validator)
      analysis_results["file_validation"] = -1
      JOptionPane.showMessageDialog(@pophealth_jframe,
        "There currently is not a CCR Schema file setup in the popHealth importer\n" + 
        "In order to support CCR Schema validation, you should purchase a CCR Schema\n" +
        "file from the ASTM website http://www.astm.org/Standards/E2369.htm and put\n" +
        "your CCR Schema file in the file system directory\n" + 
        "pilot_toolkit/resources/xml_schema/ccr/infrastructure/ccr.xsd",
        "popHealth: Missing CCR Schema XSD File",
        JOptionPane::WARNING_MESSAGE)
    else
      analysis_results["file_validation"] = files.size - file_validation_errors
    end
    @pophealth_jframe.update_analysis_results(analysis_results)
    @pophealth_jframe.enable_play
    @pophealth_jframe.set_analysis_progress_bar(0)
  end

  def update_analysis_results(patient_summary_report, analysis_results)
    patient_summary_report.sections.keys.each do |section|
      if (patient_summary_report.respond_to?(section) && patient_summary_report.send(section))
        if ! patient_summary_report.send(section).entries.empty?
          analysis_results["#{section}_present"] += 1 if analysis_results["#{section}_present"]
        end
        if patient_summary_report.send(section).num_coded_entries > 0
          analysis_results["#{section}_coded"] += 1 if analysis_results["#{section}_coded"]
        end
        if patient_summary_report.send(section).mu_coded_entries.size > 0
          analysis_results["#{section}_mu_compliant"] += 1 if analysis_results["#{section}_mu_compliant"]
        end
      end
    end
  end

  def prime_analysis_results
    analysis_results = {
      "number_files"                => 0.0,
      "file_validation"             => 0.0,
      "allergies_present"           => 0.0,
      "allergies_coded"             => 0.0,
      "allergies_mu_compliant"      => 0.0,
      "encounters_present"          => 0.0,
      "encounters_coded"            => 0.0,
      "encounters_mu_compliant"     => 0.0,
      "conditions_present"          => 0.0,
      "conditions_coded"            => 0.0,
      "conditions_mu_compliant"     => 0.0,
      "lab_results_present"         => 0.0,
      "lab_results_coded"           => 0.0,
      "lab_results_mu_compliant"    => 0.0,
      "medications_present"         => 0.0,
      "medications_coded"           => 0.0,
      "medications_mu_compliant"    => 0.0,
      "immunizations_present"       => 0.0,
      "immunizations_coded"         => 0.0,
      "immunizations_mu_compliant"  => 0.0,
      "procedures_present"          => 0.0,
      "procedures_coded"            => 0.0,
      "procedures_mu_compliant"     => 0.0,
      "vital_signs_present"         => 0.0,
      "vital_signs_coded"           => 0.0,
      "vital_signs_mu_compliant"    => 0.0
    }
  end

end
