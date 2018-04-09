class BuildBackgroundCommitJob < ApplicationJob
  queue_as :default

  rescue_from(StandardError) do |exception|
    puts "Background job failed!"
    puts "#{exception.message}"
    puts "#{exception.backtrace.join("\n")}"
    Bugsnag.notify(exception)
    raise exception
  end

  def perform(build)
    @build = build
    create_diffs_for_build
    @build.temporary = false
    @build.save
    @build.update_github_commit_status
    results = PluginManager.instance.for_project(@build.project).run_build_commited_hook(@build)
    unless results[:errors].blank?
      Bugsnag.notify(Exception.new("Build Commit Hook Plugin Failed:  #{results[:errors]}"))
    end
  end

  private
  # Find correct image to compare to
  def get_base_image_for_test_image(image)
    @build.base_images.where(test_key: image.test_key).last
  end

  def create_diffs_for_build
    if @build.is_branch_build
      preapproved_images = @build.preapproved_images_for_branch
      apply_singular_preapprovals(preapproved_images)
      create_branch_build_diffs(preapproved_images)
    else
      previous_preapprovals = @build.previous_preapprovals_for_pull_request
      create_pr_diffs(previous_preapprovals)
    end

    create_diffs_for_removed_tests
  end

  def create_branch_build_diffs(preapproved_images)
    @build.test_images.find_each(batch_size: 500) do |image|
      base = get_base_image_for_test_image(image)
      images = preapproved_images[image.test_key]
      if base.nil?
        handle_new_image_added(image)
      elsif !images.blank? # Single preapprovals have already been removed
        images.each do |preapproved|
          create_diff(preapproved, image, true) # Force diffs to show even if they're the same, for context of multiple preapprovals
        end
      else
        create_diff(base, image, false)
      end
    end
  end

  def create_pr_diffs(previous_preapprovals)
    @build.test_images.find_each(batch_size: 500) do |image|
      base = get_base_image_for_test_image(image)
      if base.nil?
        handle_new_image_added(image)
        next
      else
        diff = create_diff(base, image, false)
        previous = previous_preapprovals[image.test_key]
        if previous and not diff.nil? # See if the previous matches the current and is being compared to the same base. If it is, approve the diff
          previous_diff = previous.build.diffs.where(new_image: previous).last
          if !previous_diff.nil? and previous_diff.old_image == diff.old_image
            _, score = compare_images(previous, image)
            if score == 0
              previous_approval_user = previous_diff.approved_by
              diff.approve(previous_approval_user)
            end
          end
        end
      end
    end

    # Now clear previous preapprovals, since the new build supersedes it
    previous_preapprovals.each do |_, image|
      image.clear_preapproval_information(false)
      image.save
    end
  end

  # create diffs against a blank image for the removed tests. Users will then have to approve the removal of tests
  def create_diffs_for_removed_tests
    removed_tests = @build.get_base_images_not_uploaded
    puts "#{removed_tests.size} removed tests, creating diffs"
    removed_tests.each do |old_image|
      new_image = create_matching_blank_image(old_image)
      create_diff(old_image, new_image, true)
    end
  end

  # create diff against blank image. Mark image as blank so view can custom handle it
  def handle_new_image_added(new_image)
    return if @build.dev_build # TODO is this still needed?
    # create a white image that has the same dimensions as the new image
    old_image = create_matching_blank_image(new_image)
    create_diff(old_image, new_image, true)
  end

  def create_matching_blank_image(image_to_copy)
    new_image_file_path = image_to_copy.image.path
    copy_image = Magick::Image.ping(new_image_file_path).first
    blank_image = Image.new(copy_image.columns, copy_image.rows) {self.background_color = 'white'}
    blank_file = create_image_file(blank_image, image_to_copy.image_file_name)
    return_image = TestImage.create(image: blank_file, build_id: @build.id, test_id: image_to_copy.test_id, test_key: image_to_copy.test_key, is_blank_image: true)
    return_image.md5 = Digest::MD5.file(return_image.image.path).hexdigest
    return_image.save
    return_image
  end

  def apply_singular_preapprovals(preapproved_images)
    preapproval_applied = false
    preapproved_images.delete_if do |key, images|
      if images.size == 1
        image = images.first
        image.approved = true
        image.mark_test_has_base_image
        image.clear_preapproval_information(true)
        image.save
        preapproval_applied = true
        true
      else
        false
      end
    end
    # Recalculate base images, since the preapprovals happened
    if preapproval_applied
      @build.base_images = @build.project.calculate_base_images
      @build.save
    end
  end

  def create_diff(old_image, new_image, force)
    return nil unless old_image && new_image
    difference_image, score = compare_images(old_image, new_image)
    if score == 0 && !force
      @build.successful_tests.push(new_image)
      return nil
    else
      # Be sure to save the image and all of its changes to the database
      new_image.save
    end
    differences_file = create_image_file(difference_image, 'differences.png')
    Diff.create(old_image: old_image, new_image: new_image, differences: differences_file, build: @build)
  end

  # It Creates two imagelist and compare it using Absolute error metrics.
  # It returns an array of two elements, first one is the difference image and second one is the score
  def compare_images(baseline_image, candidate_image)
    baseline_image = ImageList.new(baseline_image.image.path).first
    candidate_image = ImageList.new(candidate_image.image.path).first
    baseline_image.fuzz = '0%'
    baseline_image.compare_channel(candidate_image, AbsoluteErrorMetric)
  end

  # It creates a blob of the difference image. It then converts the blob into a String IO, which acts like a file
  def create_image_file(image, filename)
    image_blob = image.to_blob { |image_info| image_info.format = 'PNG' }
    string_io = StringIO.new(image_blob)
    string_io.class.class_eval { attr_accessor :original_filename, :content_type }
    string_io.original_filename = filename
    string_io.content_type = 'image/png'
    string_io
  end
end