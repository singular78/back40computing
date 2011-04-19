/******************************************************************************
 * 
 * Copyright 2010-2011 Duane Merrill
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License. 
 * 
 * For more information, see our Google Code project site: 
 * http://code.google.com/p/back40computing/
 * 
 ******************************************************************************/


/******************************************************************************
 * Simple test utilities for reduction
 ******************************************************************************/

#pragma once

#include <stdio.h> 

// Reduction includes
#include <b40c/reduction_enactor.cuh>

// Test utils
#include "b40c_test_util.h"

/******************************************************************************
 * Test wrappers for binary, associative operations
 ******************************************************************************/

template <typename T>
struct Sum
{
	static __host__ __device__ __forceinline__ T Op(const T &a, const T &b)
	{
		return a + b;
	}
};

template <typename T>
struct Max
{
	static __host__ __device__ __forceinline__ T Op(const T &a, const T &b)
	{
		return (a > b) ? a : b;
	}
};


/******************************************************************************
 * Utility Routines
 ******************************************************************************/

/**
 * Timed reduction.  Uses the GPU to copy the specified vector of elements for the given
 * number of iterations, displaying runtime information.
 */
template <
	typename T,
	T BinaryOp(const T&, const T&),
	b40c::reduction::ProbSizeGenre PROB_SIZE_GENRE>
double TimedReduction(
	T *h_data,
	T *h_reference,
	size_t num_elements,
	int max_ctas,
	bool verbose,
	int iterations)
{
	using namespace b40c;

	// Allocate device storage
	T *d_src, *d_dest;
	if (util::B40CPerror(cudaMalloc((void**) &d_src, sizeof(T) * num_elements),
		"TimedReduction cudaMalloc d_src failed: ", __FILE__, __LINE__)) exit(1);
	if (util::B40CPerror(cudaMalloc((void**) &d_dest, sizeof(T)),
		"TimedReduction cudaMalloc d_dest failed: ", __FILE__, __LINE__)) exit(1);

	// Create enactor
	ReductionEnactor reduction_enactor;

	// Move a fresh copy of the problem into device storage
	if (util::B40CPerror(cudaMemcpy(d_src, h_data, sizeof(T) * num_elements, cudaMemcpyHostToDevice),
		"TimedReduction cudaMemcpy d_src failed: ", __FILE__, __LINE__)) exit(1);

	// Perform a single iteration to allocate any memory if needed, prime code caches, etc.
	reduction_enactor.DEBUG = true;
	reduction_enactor.template Enact<T, BinaryOp, PROB_SIZE_GENRE>(
		d_dest, d_src, num_elements, max_ctas);
	reduction_enactor.DEBUG = false;

	// Perform the timed number of iterations

	cudaEvent_t start_event, stop_event;
	cudaEventCreate(&start_event);
	cudaEventCreate(&stop_event);

	double elapsed = 0;
	float duration = 0;
	for (int i = 0; i < iterations; i++) {

		// Start timing record
		cudaEventRecord(start_event, 0);

		// Call the reduction API routine
		reduction_enactor.template Enact<T, BinaryOp, PROB_SIZE_GENRE>(
			d_dest, d_src, num_elements, max_ctas);

		// End timing record
		cudaEventRecord(stop_event, 0);
		cudaEventSynchronize(stop_event);
		cudaEventElapsedTime(&duration, start_event, stop_event);
		elapsed += (double) duration;
	}

	// Display timing information
	double avg_runtime = elapsed / iterations;
	double throughput = ((double) num_elements) / avg_runtime / 1000.0 / 1000.0;
	printf("\nB40C reduction: %d iterations, %lu elements, ", iterations, (unsigned long) num_elements);
    printf("%f GPU ms, %f x10^9 elts/sec, %f x10^9 B/sec, ",
		avg_runtime, throughput, throughput * sizeof(T));

    // Clean up events
	cudaEventDestroy(start_event);
	cudaEventDestroy(stop_event);

    // Copy out data
	T h_dest[1];
    if (util::B40CPerror(cudaMemcpy(h_dest, d_dest, sizeof(T), cudaMemcpyDeviceToHost),
		"TimedReduction cudaMemcpy d_dest failed: ", __FILE__, __LINE__)) exit(1);

    // Free allocated memory
    if (d_src) cudaFree(d_src);
    if (d_dest) cudaFree(d_dest);

	// Flushes any stdio from the GPU
	cudaThreadSynchronize();

	// Display copied data
	if (verbose) {
		printf("\n\nReduction: ");
		PrintValue(h_dest[0]);
		printf(", Reference: ");
		PrintValue(h_reference[0]);
		printf("\n\n");
	}

    // Verify solution
	CompareResults(h_dest, h_reference, 1, true);
	printf("\n");
	fflush(stdout);

	return throughput;
}


