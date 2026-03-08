import SwiftUI
import UIKit
import CoreML
import Vision
import CoreImage

struct ContentView: View {
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var savedImages: [UIImage] = []
    //@State private var showSavedImages = false
    @State private var predictionText = ""
    @State private var verificationText = ""

    // Your 6 class labels from the model metadata
    let classLabels = ["glass", "paper", "cardboard", "plastic", "metal", "trash"]

    var body: some View {
        NavigationStack {
            VStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 300)
                }

                Text(predictionText)
                    .padding()
                    .multilineTextAlignment(.center)
                
                //Text(verificationText)
                   // .padding()
                   // .multilineTextAlignment(.center)

                Button("Open Camera") { showCamera = true }
                    .padding()

                //Button(showSavedImages ? "Hide Saved Images" : "Show Saved Images") {
                    //if !showSavedImages { savedImages = loadImages() }
                    //showSavedImages.toggle()
               // }

                //if showSavedImages {
                    //List(savedImages.indices, id: \.self) { i in
                       // Image(uiImage: savedImages[i])
                            //.resizable()
                            //.scaledToFit()
                           // .frame(height: 120)
                  //  }
                //}
            }
            .navigationTitle("Camera + Trash Detection")
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $image)
        }
        .onChange(of: image) { newImage in
            if let img = newImage {
                saveImageToDocuments(image: img)
                runObjectDetection(on: img)
                runObjectVerify(on: img)
            }
        }
    }

    // MARK: - Object Detection (raw YOLO output, no NMS)
    func runObjectDetection(on image: UIImage) {
        // 1. Resize image to model's expected input: 320x320
        guard let resized = resizeImage(image, to: CGSize(width: 320, height: 320)),
              let pixelBuffer = resized.toCVPixelBuffer() else {
            predictionText = "Failed to prepare image"
            return
        }

        do {
            let config = MLModelConfiguration()
            let model = try best(configuration: config)

            // 2. Run the model directly (not via Vision)
            let input = bestInput(image: pixelBuffer)
            let output = try model.prediction(input: input)

            // 3. Parse raw output tensor: shape is [1, 10, num_anchors]
            //    10 = 4 (bbox: cx,cy,w,h) + 6 (class scores)
            let rawOutput = output.var_910  // MLMultiArray
            parsePredictions(rawOutput)

        } catch {
            predictionText = "ML error: \(error.localizedDescription)"
            print("ML error:", error)
        }
    }
    
    func runObjectVerify(on image: UIImage) {

        guard let ciImage = CIImage(image: image) else { return }

        do {
            let model = try VNCoreMLModel(for: yolov8m().model) // Replace with your COCO model

            let request = VNCoreMLRequest(model: model) { request, error in
                guard let results = request.results as? [VNRecognizedObjectObservation],
                      let topObject = results.first,  // Take only the first (highest confidence)
                      let label = topObject.labels.first,
                      label.confidence > 0.5 else {
                    DispatchQueue.main.async {
                        verificationText = "No object detected"
                    }
                    return
                }
                DispatchQueue.main.async {
                    predictionText = "\(label.identifier) (\(Int(label.confidence * 100))%)"
                }
            }

            let handler = VNImageRequestHandler(ciImage: ciImage)
            try handler.perform([request])

        } catch {
            print("ML error:", error)
        }
    }
    

    func parsePredictions(_ output: MLMultiArray) {
        // Output shape: [1, 10, num_anchors]
        // Axis 1: indices 0-3 = bbox (cx,cy,w,h), indices 4-9 = class scores
        let numAnchors = output.shape[2].intValue
        let numClasses = classLabels.count  // 6

        var bestConfidence: Float = 0.5  // confidence threshold
        var bestLabel = ""

        for a in 0..<numAnchors {
            // Find best class score for this anchor
            for c in 0..<numClasses {
                // Index into [1, 10, numAnchors]: offset = 0*(10*numAnchors) + (4+c)*numAnchors + a
                let idx = (4 + c) * numAnchors + a
                let score = output[idx].floatValue

                if score > bestConfidence {
                    bestConfidence = score
                    bestLabel = classLabels[c]
                }
            }
        }

        DispatchQueue.main.async {
            if bestLabel.isEmpty {
                predictionText = "No object detected"
            } else {
                predictionText = "\(bestLabel) (\(Int(bestConfidence * 100))%)"
            }
        }
    }
}

// MARK: - Image Resize Helper
func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
    image.draw(in: CGRect(origin: .zero, size: size))
    let resized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return resized
}

// MARK: - UIImage → CVPixelBuffer
extension UIImage {
    func toCVPixelBuffer() -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width), Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        ctx?.draw(cgImage!, in: CGRect(origin: .zero, size: size))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }
}

// MARK: - Image Picker, Save/Load (unchanged)
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.image = img }
            picker.dismiss(animated: true)
        }
    }
}

func saveImageToDocuments(image: UIImage) {
    guard let data = image.jpegData(compressionQuality: 0.9) else { return }
    let filename = UUID().uuidString + ".jpg"
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(filename)
    try? data.write(to: url)
}

func loadImages() -> [UIImage] {
    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return [] }
    return files.compactMap { UIImage(contentsOfFile: $0.path) }
}
