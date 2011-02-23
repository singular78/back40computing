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
 * Tuned Reduction Enactor
 ******************************************************************************/

#pragma once

#include <stdio.h>
#include <limits.h>

#include "reduction_api_enactor.cuh"
#include "reduction_api_granularity.cuh"
#include "reduction_granularity_tuned.cuh"

namespace b40c {

using namespace reduction;


/******************************************************************************
 * ReductionEnactorTuned Declaration
 ******************************************************************************/

/**
 * Tuned reduction enactor class.
 */
class ReductionEnactorTuned :
	public ReductionEnactor<ReductionEnactorTuned>,
	public Architecture<__B40C_CUDA_ARCH__, ReductionEnactorTuned>
{
protected:

	//---------------------------------------------------------------------
	// Members
	//---------------------------------------------------------------------

	// Typedefs for base classes
	typedef ReductionEnactor<ReductionEnactorTuned> 					BaseEnactorType;
	typedef Architecture<__B40C_CUDA_ARCH__, ReductionEnactorTuned> 	BaseArchType;

	// Befriend our base types: they need to call back into a
	// protected methods (which are templated, and therefore can't be virtual)
	friend class BaseEnactorType;
	friend class BaseArchType;

	// Type for encapsulating operational details regarding an invocation
	template <ProblemSize _PROBLEM_SIZE> struct Detail;

	// Type for encapsulating storage details regarding an invocation
	struct Storage;


	//-----------------------------------------------------------------------------
	// Reduction Operation
	//-----------------------------------------------------------------------------

    /**
	 * Performs a reduction pass
	 */
	template <typename ReductionConfig>
	cudaError_t ReductionPass(
		void *d_dest,
		void *d_src,
		CtaWorkDistribution<typename ReductionConfig::SizeT> &work,
		int extra_bytes);


	//-----------------------------------------------------------------------------
	// Granularity specialization interface required by Architecture subclass
	//-----------------------------------------------------------------------------

	/**
	 * Dispatch call-back with static CUDA_ARCH
	 */
	template <int CUDA_ARCH, typename Storage, typename Detail>
	cudaError_t Enact(Storage &storage, Detail &detail);


public:

	/**
	 * Constructor.
	 */
	ReductionEnactorTuned();


	/**
	 * Enacts a reduction operation on the specified device data using the
	 * enumerated tuned granularity configuration
	 *
	 * @param d_dest
	 * 		Pointer to array of bytes to be copied into
	 * @param d_src
	 * 		Pointer to array of bytes to be copied from
	 * @param num_bytes
	 * 		Number of bytes to copy
	 * @param max_grid_size
	 * 		Optional upper-bound on the number of CTAs to launch.
	 *
	 * @return cudaSuccess on success, error enumeration otherwise
	 */
	template <ProblemSize PROBLEM_SIZE>
	cudaError_t Enact(
		void *d_dest,
		void *d_src,
		size_t num_bytes,
		int max_grid_size = 0);


	/**
	 * Enacts a reduction operation on the specified device data using the
	 * LARGE granularity configuration
	 *
	 * @param d_dest
	 * 		Pointer to array of bytes to be copied into
	 * @param d_src
	 * 		Pointer to array of bytes to be copied from
	 * @param num_bytes
	 * 		Number of bytes to copy
	 * @param max_grid_size
	 * 		Optional upper-bound on the number of CTAs to launch.
	 *
	 * @return cudaSuccess on success, error enumeration otherwise
	 */
	cudaError_t Enact(
		void *d_dest,
		void *d_src,
		size_t num_bytes,
		int max_grid_size = 0);
};



/******************************************************************************
 * ReductionEnactorTuned Implementation
 ******************************************************************************/


/**
 * Type for encapsulating operational details regarding an invocation
 */
template <ProblemSize _PROBLEM_SIZE>
struct ReductionEnactorTuned::Detail
{
	static const ProblemSize PROBLEM_SIZE = _PROBLEM_SIZE;
	int max_grid_size;

	// Constructor
	Detail(int max_grid_size = 0) : max_grid_size(max_grid_size) {}
};


/**
 * Type for encapsulating storage details regarding an invocation
 */
struct ReductionEnactorTuned::Storage
{
	void *d_dest;
	void *d_src;
	size_t num_bytes;

	// Constructor
	Storage(void *d_dest, void *d_src, size_t num_bytes) :
		d_dest(d_dest), d_src(d_src), num_bytes(num_bytes) {}
};


/**
 * Performs a reduction pass
 */
template <typename ReductionConfig>
cudaError_t ReductionEnactorTuned::ReductionPass(
	void *d_dest,
	void *d_src,
	CtaWorkDistribution<typename ReductionConfig::SizeT> &work,
	int extra_bytes)
{
	cudaError_t retval = cudaSuccess;
	int dynamic_smem = 0;
	int threads = 1 << ReductionConfig::LOG_THREADS;

	TunedReductionKernel<ReductionConfig::PROBLEM_SIZE><<<work.grid_size, threads, dynamic_smem>>>(
		d_dest, d_src, d_work_progress, work, progress_selector, extra_bytes);

	if (DEBUG) {
		retval = B40CPerror(cudaThreadSynchronize(), "ReductionEnactorTuned:: ReductionKernelTuned failed ", __FILE__, __LINE__);
	}

	return retval;
}


/**
 * Dispatch call-back with static CUDA_ARCH
 */
template <int CUDA_ARCH, typename StorageType, typename DetailType>
cudaError_t ReductionEnactorTuned::Enact(StorageType &storage, DetailType &detail)
{
	// Obtain tuned granularity type
	typedef TunedConfig<CUDA_ARCH, DetailType::PROBLEM_SIZE> ReductionConfig;
	typedef typename ReductionConfig::T T;

	int num_elements = storage.num_bytes / sizeof(T);
	int extra_bytes = storage.num_bytes - (num_elements * sizeof(T));

	// Invoke base class enact with type
	return BaseEnactorType::template Enact<ReductionConfig>(
		(T*) storage.d_dest, (T*) storage.d_src, num_elements, extra_bytes, detail.max_grid_size);
}


/**
 * Constructor.
 */
ReductionEnactorTuned::ReductionEnactorTuned()
	: BaseEnactorType::ReductionEnactor()
{
}


/**
 * Enacts a reduction operation on the specified device data using the
 * enumerated tuned granularity configuration
 */
template <ProblemSize PROBLEM_SIZE>
cudaError_t ReductionEnactorTuned::Enact(
	void *d_dest,
	void *d_src,
	size_t num_bytes,
	int max_grid_size)
{
	Detail<PROBLEM_SIZE> detail(max_grid_size);
	Storage storage(d_dest, d_src, num_bytes);

	return BaseArchType::Enact(storage, detail);
}


/**
 * Enacts a reduction operation on the specified device data using the
 * LARGE granularity configuration
 */
cudaError_t ReductionEnactorTuned::Enact(
	void *d_dest,
	void *d_src,
	size_t num_bytes,
	int max_grid_size)
{
	// Hybrid approach
	if (num_bytes > 1024 * 2252) {
		return Enact<LARGE>(d_dest, d_src, num_bytes, max_grid_size);
	} else {
		return Enact<SMALL>(d_dest, d_src, num_bytes, max_grid_size);
	}
}



} // namespace b40c

