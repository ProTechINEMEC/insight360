const Minio = require('minio')

const client = new Minio.Client({
  endPoint: process.env.MINIO_ENDPOINT || 'localhost',
  port: parseInt(process.env.MINIO_PORT || '9000'),
  useSSL: process.env.MINIO_USE_SSL === 'true',
  accessKey: process.env.MINIO_ACCESS_KEY,
  secretKey: process.env.MINIO_SECRET_KEY,
})

const BUCKET = process.env.MINIO_BUCKET || 'insight360-files'

async function ensureBucket() {
  const exists = await client.bucketExists(BUCKET)
  if (!exists) {
    await client.makeBucket(BUCKET, 'us-east-1')
    console.log(`MinIO bucket '${BUCKET}' created`)

    // Bucket policy: private (no public access)
    const policy = JSON.stringify({
      Version: '2012-10-17',
      Statement: [{
        Effect: 'Deny',
        Principal: '*',
        Action: 's3:GetObject',
        Resource: [`arn:aws:s3:::${BUCKET}/*`],
        Condition: { StringNotEquals: { 'aws:SourceVpc': 'internal' } },
      }],
    })
    // Keep bucket private — access only via API presigned URLs
    console.log('MinIO bucket is private — files accessible via API only')
  }
}

// Upload a file
async function uploadFile(objectKey, buffer, contentType, metadata = {}) {
  await client.putObject(BUCKET, objectKey, buffer, buffer.length, {
    'Content-Type': contentType,
    ...metadata,
  })
  return objectKey
}

// Generate a presigned URL valid for `expiry` seconds (default 1 hour)
// This is the ONLY way to serve files — never expose MinIO directly
async function getPresignedUrl(objectKey, expiry = 3600) {
  return client.presignedGetObject(BUCKET, objectKey, expiry)
}

// Delete a file
async function deleteFile(objectKey) {
  await client.removeObject(BUCKET, objectKey)
}

// Check if file exists
async function fileExists(objectKey) {
  try {
    await client.statObject(BUCKET, objectKey)
    return true
  } catch {
    return false
  }
}

module.exports = { client, BUCKET, ensureBucket, uploadFile, getPresignedUrl, deleteFile, fileExists }
