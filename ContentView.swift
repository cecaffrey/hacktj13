import SwiftUI
import UIKit

struct ContentView: View {

    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var savedImages: [UIImage] = []
    @State private var showSavedImages = false

    var body: some View {

        NavigationStack {

            VStack {

                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 250)
                }

                Button("Open Camera") {
                    showCamera = true
                }
                .padding()

                Button(showSavedImages ? "Hide Saved Images" : "Show Saved Images") {

                    if showSavedImages == false {
                        savedImages = loadImages()
                    }

                    showSavedImages.toggle()
                
                }

                if showSavedImages {
                    List(savedImages.indices, id: \.self) { i in
                        Image(uiImage: savedImages[i])
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                    }
                }

            }
            .navigationTitle("Camera Capture") //Replace with actual title of app
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(image: $image)
        }
        .onChange(of: image) { newImage in
            if let img = newImage {
                saveImageToDocuments(image: img)
            }
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {

    @Binding var image: UIImage?

    func makeUIViewController(context: Context) -> UIImagePickerController {

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {

        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {

            if let img = info[.originalImage] as? UIImage {
                parent.image = img
            }

            picker.dismiss(animated: true)
        }
    }
}

func saveImageToDocuments(image: UIImage) {

    guard let data = image.jpegData(compressionQuality: 0.9) else { return }

    let filename = UUID().uuidString + ".jpg"

    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(filename)

    do {
        try data.write(to: url)
        print("Saved:", url)
    } catch {
        print("Save error:", error)
    }
}

func loadImages() -> [UIImage] {

    let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    guard let files = try? FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil
    ) else { return [] }

    return files.compactMap { url in
        UIImage(contentsOfFile: url.path)
    }
}
