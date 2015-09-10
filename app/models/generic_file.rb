# Generated by curation_concerns:models:install
class GenericFile < ActiveFedora::Base
  include ::CurationConcerns::GenericFileBehavior
  apply_schema IIIFPageSchema

  validates_with ViewingHintValidator
  makes_derivatives :create_intermediate_file

  private

    def create_intermediate_file
      case original_file.mime_type
      when 'image/tiff'
        transform_file :original_file, {
          service: {
            datastream: 'jp2',
            recipe: :default
          }
        }, processor: 'jpeg2k_image'
      end
    end
end
