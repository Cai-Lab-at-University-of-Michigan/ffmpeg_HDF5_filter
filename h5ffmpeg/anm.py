import numpy as np
import os
import h5ffmpeg as hf
from h5ffmpeg.utils import compress_and_decompress
import matplotlib.pyplot as plt
from skimage import feature, draw
from PIL import Image, ImageChops
from skimage.transform import probabilistic_hough_line
from skimage.filters import threshold_otsu, gaussian
from skimage.metrics import structural_similarity as ssim
from scipy.ndimage import gaussian_filter, generic_filter
from scipy.fftpack import dct
import warnings

warnings.filterwarnings("ignore")

def normalize(img):
    return img / np.max(img)


def analyze_content(img):
    img_norm = normalize(img)
    
    if img_norm.ndim > 2:
        img_analysis = img_norm[1] if img_norm.shape[0] >= 3 else np.mean(img_norm, axis=0)
    else:
        img_analysis = img_norm
    
    try:
        thresh = threshold_otsu(img_analysis)
        binary = img_analysis > thresh
        structure_density = np.mean(binary)
    except:
        structure_density = np.sum(img_analysis > np.mean(img_analysis)) / img_analysis.size
    
    background = img_analysis * (1 - binary) if 'binary' in locals() else img_analysis * (img_analysis < np.percentile(img_analysis, 25))
    background_pixels = background[background > 0]
    background_uniformity = 1 - np.std(background_pixels) if len(background_pixels) > 0 else 0.5
    
    from scipy import ndimage
    gx = ndimage.sobel(img_analysis, axis=1)
    gy = ndimage.sobel(img_analysis, axis=0)
    gradient_mag = np.hypot(gx, gy)
    detail_level = np.percentile(gradient_mag / np.max(gradient_mag), 75)
    
    return {
        'structure_density': structure_density,
        'background_uniformity': background_uniformity,
        'detail_level': detail_level
    }


def extract_patches(img, num_samples=5, patch_size=(128, 128)):
    if img.ndim > 2:
        channels, h, w = img.shape
    else:
        h, w = img.shape
        channels = 1
        img = img.reshape((1, h, w))
    
    detail_map = np.zeros((h, w))
    analysis_channel = img[1] if channels >= 3 else img[0]
    
    edges = feature.canny(analysis_channel, sigma=1.5)
    detail_map += edges * 2
    
    texture = generic_filter(analysis_channel, np.std, size=7)
    detail_map += texture / np.max(texture)
    
    detail_map = detail_map / np.max(detail_map)
    high_detail = detail_map > np.percentile(detail_map, 75)
    
    patches = []
    high_detail_coords = np.argwhere(high_detail)
    np.random.shuffle(high_detail_coords)
    high_detail_samples = min(int(num_samples * 0.7), len(high_detail_coords))
    
    for i in range(high_detail_samples):
        if i < len(high_detail_coords):
            y, x = high_detail_coords[i]
            y_start = min(max(0, y - patch_size[0]//2), h - patch_size[0])
            x_start = min(max(0, x - patch_size[1]//2), w - patch_size[1])
            
            patch = img[:, y_start:y_start+patch_size[0], x_start:x_start+patch_size[1]]
            patches.append(patch)
    
    remaining_samples = num_samples - len(patches)
    for _ in range(remaining_samples):
        y_start = np.random.randint(0, h - patch_size[0] + 1)
        x_start = np.random.randint(0, w - patch_size[1] + 1)
        patch = img[:, y_start:y_start+patch_size[0], x_start:x_start+patch_size[1]]
        patches.append(patch)
    
    return np.concatenate(patches, axis=0)


def detect_blockiness(img, block_sizes=[8, 16]):
    img_norm = normalize(img)
    channels = [img_norm[i] for i in range(img_norm.shape[0])] if img_norm.ndim > 2 else [img_norm]
    total_score = 0
    
    for channel in channels:
        gx = np.abs(np.diff(channel, axis=1, prepend=channel[:, :1]))
        gy = np.abs(np.diff(channel, axis=0, prepend=channel[:1, :]))
        
        block_score = 0
        for block_size in block_sizes:
            h_pattern = np.mean(gx[:, block_size-1::block_size])
            h_non_pattern = np.mean(np.delete(gx, np.arange(block_size-1, gx.shape[1], block_size), axis=1))
            h_ratio = h_pattern / (h_non_pattern + 1e-8)
            
            v_pattern = np.mean(gy[block_size-1::block_size, :])
            v_non_pattern = np.mean(np.delete(gy, np.arange(block_size-1, gy.shape[0], block_size), axis=0))
            v_ratio = v_pattern / (v_non_pattern + 1e-8)
            
            block_score += max(0, h_ratio - 1.2) + max(0, v_ratio - 1.2)
        
        def dct_blockiness(img, block_size=8):
            h, w = img.shape
            score = 0
            
            for i in range(0, h-block_size, block_size):
                for j in range(0, w-block_size, block_size):
                    block = img[i:i+block_size, j:j+block_size]
                    dct_block = dct(dct(block.T, norm='ortho').T, norm='ortho')
                    high_freq = np.abs(dct_block[4:, 4:])
                    low_freq = np.abs(dct_block[:4, :4])
                    
                    if np.mean(high_freq) > 0.05 * np.mean(low_freq):
                        score += 1
            
            blocks_analyzed = ((h // block_size) * (w // block_size))
            return score / max(1, blocks_analyzed)
        
        dct_score = dct_blockiness(channel)
        
        smooth = gaussian(channel, sigma=0.5)
        diff = np.abs(channel - smooth)
        
        h_disc = np.sum(np.mean(diff[:, block_sizes[0]-1::block_sizes[0]], axis=1))
        v_disc = np.sum(np.mean(diff[block_sizes[0]-1::block_sizes[0], :], axis=0))
        
        h_disc /= channel.shape[0]
        v_disc /= channel.shape[1]
        
        struct_score = (h_disc + v_disc) / 2
        channel_score = 0.4 * block_score + 0.4 * dct_score + 0.2 * struct_score
        total_score += channel_score
    
    return total_score / len(channels)


def analyze_structure_preservation(original, compressed):
    if original.ndim > 2:
        orig_analysis = original[1] if original.shape[0] >= 3 else np.mean(original, axis=0)
        comp_analysis = compressed[1] if compressed.shape[0] >= 3 else np.mean(compressed, axis=0)
    else:
        orig_analysis = original
        comp_analysis = compressed
    
    orig_norm = orig_analysis / np.max(orig_analysis)
    comp_norm = comp_analysis / np.max(comp_analysis)
    
    edges_orig = feature.canny(orig_norm, sigma=1.0)
    edges_comp = feature.canny(comp_norm, sigma=1.0)
    
    true_positive = np.sum(edges_orig & edges_comp)
    false_negative = np.sum(edges_orig & ~edges_comp)
    false_positive = np.sum(~edges_orig & edges_comp)
    
    precision = true_positive / (true_positive + false_positive + 1e-10)
    recall = true_positive / (true_positive + false_negative + 1e-10)
    f1_boundary = 2 * (precision * recall) / (precision + recall + 1e-10)
    
    orig_smooth = gaussian_filter(orig_norm, sigma=2.0)
    comp_smooth = gaussian_filter(comp_norm, sigma=2.0)
    
    orig_detail = orig_norm - orig_smooth
    comp_detail = comp_norm - comp_smooth
    
    detail_ssim = ssim(orig_detail, comp_detail, data_range=np.max(orig_detail) - np.min(orig_detail))
    
    try:
        thresh_orig = threshold_otsu(orig_norm)
        mask_orig = orig_norm > thresh_orig
    except:
        mask_orig = orig_norm > np.mean(orig_norm)
    
    def kl_divergence(p, q):
        p = p + 1e-10
        q = q + 1e-10
        p = p / np.sum(p)
        q = q / np.sum(q)
        return np.sum(p * np.log(p / q))
    
    hist_orig, bins = np.histogram(orig_norm[mask_orig], bins=50, density=True)
    hist_comp, _ = np.histogram(comp_norm[mask_orig], bins=bins, density=True)
    
    kl_div = (kl_divergence(hist_orig, hist_comp) + kl_divergence(hist_comp, hist_orig)) / 2
    intensity_similarity = np.exp(-kl_div)
    
    return {
        'boundary_preservation': f1_boundary,
        'detail_preservation': detail_ssim,
        'intensity_preservation': intensity_similarity,
        'overall_quality': (f1_boundary + detail_ssim + intensity_similarity) / 3
    }


def plot_results(grains, blockiness, perceptual, compression, combined, best_grain):
    plt.figure(figsize=(14, 10))
    gs = plt.GridSpec(2, 2, height_ratios=[1, 1])
    
    ax1 = plt.subplot(gs[0, 0])
    ax1.plot(grains, blockiness, 'ro-', linewidth=2, markersize=6)
    ax1.set_ylabel('Blockiness Score\n(lower is better)', fontsize=10)
    ax1.set_title('Artifact Detection', fontsize=12)
    ax1.grid(True, alpha=0.3)
    
    ax2 = plt.subplot(gs[0, 1])
    ax2.plot(grains, perceptual, 'go-', linewidth=2, markersize=6)
    ax2.set_ylabel('Perceptual Quality\n(higher is better)', fontsize=10)
    ax2.set_title('Structure Preservation', fontsize=12)
    ax2.grid(True, alpha=0.3)
    
    ax3 = plt.subplot(gs[1, 0])
    ax3.plot(grains, combined, 'bo-', linewidth=2, markersize=6)
    ax3.axvline(x=best_grain, color='black', linestyle='--', linewidth=2, 
                label=f'Best grain: {best_grain}')
    ax3.set_xlabel('Film Grain Parameter', fontsize=10)
    ax3.set_ylabel('Combined Score\n(higher is better)', fontsize=10)
    ax3.set_title('Overall Quality', fontsize=12)
    ax3.grid(True, alpha=0.3)
    ax3.legend(fontsize=10)
    
    ax4 = plt.subplot(gs[1, 1])
    ax4.plot(grains, compression, 'mo-', linewidth=2, markersize=6)
    ax4.axvline(x=best_grain, color='black', linestyle='--', linewidth=2)
    ax4.set_xlabel('Film Grain Parameter', fontsize=10)
    ax4.set_ylabel('Compression Ratio\n(higher is better)', fontsize=10)
    ax4.set_title('Storage Efficiency', fontsize=12)
    ax4.grid(True, alpha=0.3)
    
    ax1.annotate(f'Min: {min(blockiness):.3f}', 
                xy=(grains[np.argmin(blockiness)], min(blockiness)),
                xytext=(grains[np.argmin(blockiness)]+2, min(blockiness)*1.1),
                arrowprops=dict(facecolor='black', shrink=0.05, width=1),
                fontsize=9)
    
    ax2.annotate(f'Max: {max(perceptual):.3f}', 
                xy=(grains[np.argmax(perceptual)], max(perceptual)),
                xytext=(grains[np.argmax(perceptual)]+2, max(perceptual)*0.95),
                arrowprops=dict(facecolor='black', shrink=0.05, width=1),
                fontsize=9)
    
    os.makedirs('tmp', exist_ok=True)
    plt.tight_layout()
    plt.savefig('tmp/grain_optimization.png', dpi=150)
    plt.close()


def film_grain_optimizer(img=None, num_samples=5, quality_focus='structures', plot=False):
    if img is None:
        raise ValueError("img must be provided")
    
    print(f"Analyzing image of shape {img.shape}...")
    
    content_info = analyze_content(img)
    print("\nContent Analysis:")
    for key, value in content_info.items():
        print(f"  - {key}: {value:.3f}")
    
    print(f"\nExtracting {num_samples} representative patches...")
    img_patches = extract_patches(img, num_samples=num_samples)
    
    if content_info['detail_level'] > 0.7:
        grain_range = range(0, 31, 3)
        print("High detail content detected - using fine parameter sweep")
    elif content_info['background_uniformity'] > 0.8:
        grain_range = range(5, 51, 5)
        print("Uniform background detected - optimizing to prevent banding")
    else:
        grain_range = range(0, 51, 5)
        print("Mixed content detected - using standard parameter range")
    
    print(f"Testing grain parameters: {list(grain_range)}")
    
    original_patches = img_patches.copy()
    params = [hf.svtav1(grain=grain) for grain in grain_range]
    
    blockiness_scores = []
    compression_ratios = []
    perceptual_scores = []
    structure_scores = []
    
    raw_blockiness = detect_blockiness(original_patches)
    blockiness_scores.append(raw_blockiness)
    print(f"Raw blockiness score: {raw_blockiness:.4f}")
    
    print("\nTesting parameters:")
    print(f"{'Grain':<6} {'Blockiness':<12} {'SSIM':<12} {'Structure':<12} {'Ratio':<8}")
    print("-" * 50)
    
    for i, param in enumerate(params):
        decom_data, cs_ratio, _, _ = compress_and_decompress(img_patches, param)
        compression_ratios.append(cs_ratio)
        
        block_score = detect_blockiness(decom_data)
        blockiness_scores.append(block_score)
        
        if original_patches.ndim > 2:
            ssim_score = np.mean([
                ssim(original_patches[c], decom_data[c], data_range=np.max(original_patches[c])) 
                for c in range(original_patches.shape[0])
            ])
        else:
            ssim_score = ssim(original_patches, decom_data, data_range=np.max(original_patches))
        
        perceptual_scores.append(ssim_score)
        
        structure_metrics = analyze_structure_preservation(original_patches, decom_data)
        structure_score = structure_metrics['overall_quality']
        structure_scores.append(structure_score)
        
        print(f"{grain_range[i]:<6} {block_score:<12.4f} {ssim_score:<12.4f} "
              f"{structure_score:<12.4f} {cs_ratio:<8.2f}")
    
    norm_blockiness = [score/blockiness_scores[0] for score in blockiness_scores[1:]]
    
    if quality_focus == 'structures':
        weights = {'blockiness': 0.3, 'perceptual': 0.3, 'structure': 0.4}
        print("\nOptimizing for structure preservation")
    elif quality_focus == 'background':
        weights = {'blockiness': 0.5, 'perceptual': 0.4, 'structure': 0.1}
        print("\nOptimizing for artifact reduction")
    else:
        weights = {'blockiness': 0.4, 'perceptual': 0.3, 'structure': 0.3}
        print("\nUsing balanced approach")
    
    combined_scores = []
    for i in range(len(grain_range)):
        score = (weights['blockiness'] * (1 - norm_blockiness[i]) + 
                 weights['perceptual'] * perceptual_scores[i] +
                 weights['structure'] * structure_scores[i])
        combined_scores.append(score)
    
    best_idx = np.argmax(combined_scores)
    best_grain = grain_range[best_idx]
    
    if plot:
        plot_results(grain_range, blockiness_scores[1:], perceptual_scores, 
                    compression_ratios, combined_scores, best_grain)
    
    print(f"\nOptimal film grain parameter: {best_grain}")
    print(f"  - Blockiness: {blockiness_scores[best_idx+1]:.4f}")
    print(f"  - Perceptual quality: {perceptual_scores[best_idx]:.4f}")
    print(f"  - Structure preservation: {structure_scores[best_idx]:.4f}")
    print(f"  - Compression ratio: {compression_ratios[best_idx]:.2f}")
    
    return best_grain, {
        'content_analysis': content_info,
        'grain_range': list(grain_range),
        'blockiness_scores': blockiness_scores[1:],
        'perceptual_scores': perceptual_scores,
        'structure_scores': structure_scores,
        'compression_ratios': compression_ratios,
        'combined_scores': combined_scores
    }