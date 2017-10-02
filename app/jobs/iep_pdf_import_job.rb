require 'zip'
require 'tempfile'
require 'fileutils'

class IepPdfImportJob
  def initialize(options = {})
    @time_now = options[:time_now] || Time.now
  end

  # This imports all the IEP PDFs from a zip that
  # contains several older documents (ie., for a first-time import).
  # It will fail on any errors, log to the console and won't retry.
  def bulk_import!
    remote_filenames = ['student-documents_old.zip']

    import_ieps!(remote_filenames)
  end

  def nightly_import!
    remote_filenames = [
      'student-documents-1.zip',
      'student-documents-2.zip',
      'student-documents-3.zip',
      'student-documents-4.zip',
      'student-documents-5.zip',
      'student-documents-6.zip',
    ]

    import_ieps!(remote_filenames)
  end

  private

    def import_ieps!(remote_filenames)
      clean_up

      FileUtils.mkdir_p("tmp/data_download/unzipped_ieps")

      remote_filenames.each do |filename|
        zip_file = download(filename)
        log "got a zip: #{zip_file}"
        unzipped_count = 0

        begin
          Zip::File.open(zip_file) do |zip_file|
            zip_file.each do |entry|
              entry.extract("tmp/data_download/unzipped_ieps/#{entry.name}")
              unzipped_count += 1
            end
          end
        rescue => e
          log e.message
        end

        log "unzipped #{unzipped_count} date zips!"

        #  pdf_filenames.each do |path|
        #    parse_file_name_and_store_file(path, date_zip_filename)
        #  end
      end

      clean_up
    end

    def logger
      @iep_import_logger ||= Logger.new(STDOUT)
    end

    def log(msg)
      logger.info(msg)
    end

    def parse_file_name_and_store_file(path_to_file, date_zip_filename)
      file_info = IepFileNameParser.new(path_to_file, date_zip_filename)
      file_info.check_iep_at_a_glance

      IepStorer.new(
        path_to_file: path_to_file,
        file_name: file_info.file_name,
        local_id: file_info.local_id,
        client: s3,
        logger: logger
      ).store
    end

    def s3
      @client ||= Aws::S3::Client.new
    end

    def download(remote_filename)
      client = SftpClient.for_x2
      log "have a client!"

      begin
        client.download_file(remote_filename)
        log "downloaded a file!"
      rescue RuntimeError => error
        message = error.message

        if message.include?('no such file')
          log error.message
          log 'No file found but no worries, just means no educators added IEPs into the EasyIEP system that particular day.'
        else
          raise error
        end
      end

      return File.open("tmp/data_download/#{remote_filename}")
    end

    def clean_up
      FileUtils.rm_rf(Rails.root.join('tmp/data_download/unzipped_ieps'))
      FileUtils.rm_rf(Rails.root.join('tmp/data_download/student-documents*'))
    end

end
