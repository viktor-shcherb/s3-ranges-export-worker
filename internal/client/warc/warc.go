package warc

// FIXME: this is an approximate implementation, redo once the requirements solidify

import (
	"context"
	"fmt"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	"io"
)

type Chunk struct {
	Bucket string
	Key    string
	Offset int64
	Length int64
}

func FetchWarcChunk(ctx context.Context, client *s3.Client, c Chunk) (io.ReadCloser, error) {
	// Build the “Range: bytes=start-end” header
	start := c.Offset
	end := c.Offset + c.Length - 1
	rangeHdr := fmt.Sprintf("bytes=%d-%d", start, end)

	out, err := client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: &c.Bucket,
		Key:    &c.Key,
		Range:  &rangeHdr,
	})
	if err != nil {
		return nil, err
	}
	// out.Body implements io.ReadCloser: exactly your slice, gzipped
	return out.Body, nil
}

func main() {
	ctx := context.Background()
	cfg, _ := config.LoadDefaultConfig(ctx, config.WithRegion("us-east-1"))
	cli := s3.NewFromConfig(cfg)

	chunk := Chunk{
		Bucket: "commoncrawl",
		Key:    "crawl-data/CC-MAIN-2024-33/segments/.../warc/...warc.gz",
		Offset: 12345678,
		Length: 9876,
	}
	reader, err := FetchWarcChunk(ctx, cli, chunk)
	if err != nil {
		panic(err)
	}
	defer reader.Close()
	// Now you can wrap reader in a gzip.Reader and warcio to extract the HTML record.
}
