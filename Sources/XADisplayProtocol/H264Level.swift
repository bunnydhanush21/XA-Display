import Foundation

/// H264LevelLimits.
public enum H264LevelLimits {
    public static func maxMacroblocksPerFrame(_ level: String) -> Int? {
        switch level {
        case "3.1": return 3_600
        case "4.0": return 8_192
        case "4.1": return 8_192
        case "4.2": return 8_704
        case "5.0": return 22_080
        case "5.1": return 36_864
        default: return nil
        }
    }

    public static func maxMacroblocksPerSecond(_ level: String) -> Int? {
        switch level {
        case "3.1": return 108_000
        case "4.0", "4.1": return 245_760
        case "4.2": return 522_240
        case "5.0": return 589_824
        case "5.1": return 983_040
        default: return nil
        }
    }

    public static func fits(width: Int, height: Int, level: String) -> Bool {
        guard let maxFS = maxMacroblocksPerFrame(level) else { return false }
        let macroblocks = ((width + 15) / 16) * ((height + 15) / 16)
        return macroblocks <= maxFS
    }
}

/// Lowest H.264 level whose MaxFS and MaxMBPS both hold the picture. The names match VideoToolbox `H264_Main_*` constants.
public enum H264LevelChoice {
    public static func level(width: Int, height: Int, fps: Int) -> String? {
        let macroblocks = ((width + 15) / 16) * ((height + 15) / 16)
        let perSecond = macroblocks * max(fps, 1)
        for candidate in ["3.1", "4.0", "4.1", "4.2", "5.0", "5.1"] {
            guard let maxFrame = H264LevelLimits.maxMacroblocksPerFrame(candidate),
                let maxSecond = H264LevelLimits.maxMacroblocksPerSecond(candidate)
            else { continue }
            if macroblocks <= maxFrame && perSecond <= maxSecond { return candidate }
        }
        return nil
    }

    public static func videoToolboxAccepts(profileLevelName: String) -> Bool {
        [
            "H264_Baseline_3_1", "H264_Main_3_1", "H264_Main_4_1", "H264_Main_4_2", "H264_Main_5_0", "H264_Main_5_1", "H264_High_5_0", "H264_High_5_1"
        ].contains(profileLevelName)
    }
}
