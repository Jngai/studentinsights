class ImportTask

  def initialize(options:)
    # options["school"] is an optional filter; imports all schools if nil
    @school = options.fetch("school", nil)

    # options["source"] describes which external data sources to import from
    @source = options.fetch("source", ["x2", "star"])

    # options["test_mode"] is for the test suite and supresses log output
    @test_mode = options.fetch("test_mode", false)

    # options["progress_bar"] shows a command line progress bar
    @progress_bar = options.fetch("progress_bar", false)
  end

  def connect_transform_import
    validate_district_option
    seed_schools_if_needed
    validate_school_options
    set_up_record
    set_up_report
    import_all_the_data
    run_update_tasks
    print_final_report
  end

  private

  ## VALIDATE DEVELOPER INPUT ##

  def validate_district_option
    # The LoadDistrictConfig class uses `fetch`, which will validate the
    # district option for us
    LoadDistrictConfig.new.load_yml
  end

  def seed_schools_if_needed
    School.seed_schools_for_district if School.count == 0
  end

  def validate_school_options
    # If the developer is passing in a list of school IDs to filter by,
    # we check that the IDs are valid and the schools exist in the database.

    # If there's no filtering by school, we take all the school IDs listed in
    # the district config file and make sure those schools are in the database.

    school_ids.each { |id| School.find_by!(local_id: id) }
  end

  def school_ids
    return @school if @school.present?

    LoadDistrictConfig.new.schools.map { |school| school["local_id"] }
  end

  ## SET UP COMMAND LINE REPORT AND DATABASE RECORD ##

  def log
    @test_mode ? LogHelper::Redirect.instance.file : STDOUT
  end

  def set_up_record
    @record ||= ImportRecord.create(time_started: DateTime.current)
  end

  def set_up_report
    models = [ Student, StudentAssessment, DisciplineIncident, Absence, Tardy, Educator, School, Course, Section, StudentSectionAssignment, EducatorSectionAssignment ]

    log = @test_mode ? LogHelper::Redirect.instance.file : STDOUT

    @report = ImportTaskReport.new(
      models_for_report: models,
      record: @record,
      log: log,
    )

    @report.print_initial_report
  end

  ## IMPORT ALL THE DATA ##

  def file_import_class_to_client(import_class)
    return SftpClient.for_x2 if import_class.in?(X2Importers.list)

    return SftpClient.for_star if import_class.in?(StarImporters.list)

    return nil
  end

  def import_all_the_data
    file_import_classes = UnwrapFileImporterOptions.new(@source).sort_file_import_classes
    timing_log = []

    file_import_classes.each do |file_import_class|
      file_importer = file_import_class.new(
        school_ids,
        file_import_class_to_client(file_import_class),
        log,
        @progress_bar
      )

      timing_data = { importer: file_importer.class.name, start_time: Time.current }

      begin
        file_importer.import
      rescue => error
        log.write("🚨  🚨  🚨  🚨  🚨  Error! #{error}")

        extra_info =  { "importer" => file_importer.class.name }
        ErrorMailer.error_report(error, extra_info).deliver_now if Rails.env.production?
      end

      timing_data[:end_time] = Time.current
      timing_log << timing_data

      @record.update(
        importer_timing_json: timing_log.to_json,
        time_ended: DateTime.current,
      )

      @record.save!
    end
  end

  ## RUN TASKS THAT CACHE DATA ##

  def run_update_tasks
    begin
      Student.update_risk_levels!
      Student.update_recent_student_assessments
      Homeroom.destroy_empty_homerooms
    rescue => error
      ErrorMailer.error_report(error).deliver_now if Rails.env.production?
      raise error
    end
  end

  ## PRINT FINAL REPORT ##

  def print_final_report
    @report.print_final_report
  end

end
