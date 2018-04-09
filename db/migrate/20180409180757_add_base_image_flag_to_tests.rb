class AddBaseImageFlagToTests < ActiveRecord::Migration[5.1]
  def change
    add_column :test_images, :is_blank_image, :boolean, default: false
    add_column :tests, :has_base_image, :boolean, default: false

    Project.find_each do |project|
      base_image_set = get_base_images(project)
      if base_image_set.size > 0
        project.tests.find_each do |test|
          base_image = test.current_base_image
          if base_image && base_image_set.include?(base_image)
            test.has_base_image = true
            test.save
          end
        end
      end
    end
  end

  # Old way of calculating base images to update the new column flags, after this migration, server will use the new flags
  def get_base_images(project)
    images = []
    if project.builds.size == 0
      return images
    end
    project.tests.find_each do |test|
      image = base_image(test)
      images.push(image) unless image.nil?
    end
    # Sort alphabetically
    images.sort_by! { |image| image.image_file_name.downcase }
    images
  end

  def base_image(test)
    test.test_images.where(approved: true).last
  end
end