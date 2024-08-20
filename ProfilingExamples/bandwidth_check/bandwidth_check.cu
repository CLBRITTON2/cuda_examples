#include <cstdio>
#include <cstdlib>
#include <getopt.h>
#include <cuda_runtime.h>
#include <vector>

// Default values
constexpr int DEFAULT_NUM_COPY_ITERATIONS = 1000;
constexpr int DEFAULT_NUM_STREAMS = 4;
constexpr int DEFAULT_WARMUP_ITERATIONS = 10;
constexpr size_t DEFAULT_DATA_SIZE = 1 << 24; // 16M floats

void checkBandwidth(size_t dataSize, int numCopyIterations, int numStreams, int warmupIterations) {
    // Allocate pinned host memory.
    float *hData;
    ::cudaHostAlloc(&hData, dataSize * sizeof(float), cudaHostAllocDefault);

    // Populate the host array with values.
    for (size_t i = 0; i < dataSize; ++i) {
        hData[i] = static_cast<float>(i);
    }

    // Allocate device memory.
    float *dData;
    ::cudaMalloc(&dData, dataSize * sizeof(float));

    // Create CUDA events for timing purposes.
    cudaEvent_t start, stop;
    ::cudaEventCreate(&start);
    ::cudaEventCreate(&stop);

    // Create multiple CUDA streams.
    std::vector<cudaStream_t> streams(numStreams);
    for (int i = 0; i < numStreams; ++i) {
        ::cudaStreamCreate(&streams[i]);
    }

    // Perform warm-up iterations to stabilize performance.
    for (int i = 0; i < warmupIterations; ++i) {
        int streamIndex = i % numStreams;
        ::cudaMemcpyAsync(dData, hData, dataSize * sizeof(float), cudaMemcpyHostToDevice, streams[streamIndex]);
    }
    for (int i = 0; i < numStreams; ++i) {
        ::cudaStreamSynchronize(streams[i]);
    }

    // Record the start event.
    ::cudaEventRecord(start);

    // Perform data transfers using multiple streams.
    for (int i = 0; i < numCopyIterations; ++i) {
        int streamIndex = i % numStreams;
        ::cudaMemcpyAsync(dData, hData, dataSize * sizeof(float), cudaMemcpyHostToDevice, streams[streamIndex]);
    }

    // Sync all streams to ensure copy complete.
    for (int i = 0; i < numStreams; ++i) {
        ::cudaStreamSynchronize(streams[i]);
    }

    // Record the stop event.
    ::cudaEventRecord(stop);

    // Wait for the stop event to complete.
    ::cudaEventSynchronize(stop);

    // Calculate the elapsed time.
    float ms = 0;
    ::cudaEventElapsedTime(&ms, start, stop);

    // Check if ms is zero to avoid division by zero.
    if (ms > 0) {
        // Convert to GB/s.
        const float bandwidth = ((float(dataSize) * sizeof(float) * float(numCopyIterations)) / (ms * 1e6));
        printf("Bandwidth: %f GB/s\n", bandwidth);
    } else {
        printf("Bandwidth calculation error: elapsed time is zero.\n");
    }

    // Clean up.
    ::cudaFree(dData);
    ::cudaFreeHost(hData);
    for (int i = 0; i < numStreams; ++i) {
        ::cudaStreamDestroy(streams[i]);
    }
    ::cudaEventDestroy(start);
    ::cudaEventDestroy(stop);
}

int main(int argc, char* argv[]) {
    // Command-line options
    int numCopyIterations = DEFAULT_NUM_COPY_ITERATIONS;
    int numStreams = DEFAULT_NUM_STREAMS;
    int warmupIterations = DEFAULT_WARMUP_ITERATIONS;
    size_t dataSize = DEFAULT_DATA_SIZE;

    // Parse command-line arguments
    int option;
    while ((option = getopt(argc, argv, "i:s:w:d:")) != -1) {
        switch (option) {
            case 'i':
                numCopyIterations = std::atoi(optarg);
                break;
            case 's':
                numStreams = std::atoi(optarg);
                break;
            case 'w':
                warmupIterations = std::atoi(optarg);
                break;
            case 'd':
                dataSize = std::atol(optarg);
                break;
            default:
                fprintf(stderr, "Usage: %s [-i iterations] [-s streams] [-w warmup] [-d dataSize]\n", argv[0]);
                fprintf(stderr, "  -i iterations : Number of copy iterations (default: %d)\n", DEFAULT_NUM_COPY_ITERATIONS);
                fprintf(stderr, "  -s streams    : Number of streams (default: %d)\n", DEFAULT_NUM_STREAMS);
                fprintf(stderr, "  -w warmup     : Number of warm-up iterations (default: %d)\n", DEFAULT_WARMUP_ITERATIONS);
                fprintf(stderr, "  -d dataSize   : Data size in number of floats (default: %zu)\n", DEFAULT_DATA_SIZE);
                fprintf(stderr, "Examples:\n");
                fprintf(stderr, "  %s -i 2000 -s 8 -w 20 -d 33554432\n", argv[0]);
                fprintf(stderr, "  %s -d 16777216\n", argv[0]);
                exit(EXIT_FAILURE);
        }
    }

    checkBandwidth(dataSize, numCopyIterations, numStreams, warmupIterations);
    return 0;
}
