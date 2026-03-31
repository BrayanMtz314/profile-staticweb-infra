  resource "aws_s3_bucket" "firstbucket" {
    bucket = var.bucket_name
  }


  resource "aws_s3_bucket_public_access_block" "block" {
    bucket = aws_s3_bucket.firstbucket.id

    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }

  resource "aws_cloudfront_origin_access_control" "oac" {
    name                              = "demo-oac"
    description                       = "Example Policy"
    origin_access_control_origin_type = "s3"
    signing_behavior                  = "always"
    signing_protocol                  = "sigv4"
  }


  resource "aws_s3_bucket_policy" "allow_cf" {
    bucket = aws_s3_bucket.firstbucket.id
    depends_on = [ aws_s3_bucket_public_access_block.block ]
    policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Sid": "AllowCloudFrontServicePrincipalReadOnly",
        "Effect": "Allow",
        "Principal": {
          "Service": "cloudfront.amazonaws.com"
        },
        "Action": "s3:GetObject",
        "Resource": "${aws_s3_bucket.firstbucket.arn}/*",
        "Condition": {
          "StringEquals": {
            "AWS:SourceArn": aws_cloudfront_distribution.s3_distribution.arn
          }
        }
          }]})

  }


  resource "aws_cloudfront_distribution" "s3_distribution" {
    origin {
      #The domain name must be the same as the bucket name
      domain_name              = aws_s3_bucket.firstbucket.bucket_regional_domain_name
      origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
      origin_id                = local.origin_id
    }

    enabled             = true
    is_ipv6_enabled     = true
    comment             = "Some comment"
    default_root_object = "index.html"

    aliases = [var.name-static-web, "www.${var.name-static-web}"]

    default_cache_behavior {
      allowed_methods  = ["GET", "HEAD"]
      cached_methods   = ["GET", "HEAD"]
      target_origin_id = local.origin_id

      forwarded_values {
        query_string = false

        cookies {
          forward = "none"
        }
      }

      viewer_protocol_policy = "redirect-to-https"
      min_ttl                = 0
      default_ttl            = 3600
      max_ttl                = 86400
    }
  
    price_class = "PriceClass_100"

    restrictions {
      geo_restriction {
        restriction_type = "none"
      }
    }

    viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert_validation.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
    }
  }


  resource "aws_route53_zone" "primary" {
    name = var.name-static-web
  }





  resource "aws_acm_certificate" "cert" {
    domain_name       = var.name-static-web
    subject_alternative_names = ["www.${var.name-static-web}"]
    validation_method = "DNS"

    lifecycle { 
      create_before_destroy = true
    }
  }


  resource "aws_route53_record" "certificate_validation" {
    for_each = {
      for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
        name   = dvo.resource_record_name
        record = dvo.resource_record_value
        type   = dvo.resource_record_type
      }
    }

    allow_overwrite = true
    name            = each.value.name
    records         = [each.value.record]
    ttl             = 60
    type            = each.value.type
    zone_id         = aws_route53_zone.primary.zone_id
  }

  resource "aws_acm_certificate_validation" "cert_validation" {
    certificate_arn         = aws_acm_certificate.cert.arn
    validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
  }


  resource "aws_route53_record" "root" {
    zone_id = aws_route53_zone.primary.zone_id
    name    = var.name-static-web 
    type    = "A"

    alias {
      # Aquí conectamos con tu distribución de CloudFront
      name                   = aws_cloudfront_distribution.s3_distribution.domain_name
      zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
      evaluate_target_health = false
    }
  }


  resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "www.${var.name-static-web}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
