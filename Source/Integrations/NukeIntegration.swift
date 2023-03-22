//
//  NukeIntegration.swift
//  AXPhotoViewer
//
//  Created by Alessandro Nakamuta on 15/04/18.
//  Copyright © 2018 Alessandro Nakamuta. All rights reserved.
//

#if canImport(UIKit)
import UIKit
#endif
#if canImport(Nuke)
import Nuke

class NukeIntegration: NSObject, AXNetworkIntegrationProtocol {
    public weak var delegate: AXNetworkIntegrationDelegate?

    fileprivate var retrieveImageTasks
        = NSMapTable<AXPhotoProtocol, ImageTask>(keyOptions: .strongMemory, valueOptions: .strongMemory)

    func executeInBackground(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            DispatchQueue.global().async(execute: block)
        } else {
            block()
        }
    }

    typealias Progress = (_ response: ImageResponse?, _ completed: Int64, _ total: Int64) -> Void
    typealias Completion = (_ result: Result<ImageResponse, ImagePipeline.Error>) -> Void

    public func loadPhoto(_ photo: AXPhotoProtocol) {
        if photo.imageData != nil || photo.image != nil {
            executeInBackground { [weak self] in
                guard let self = self else { return }
                self.delegate?.networkIntegration(self, loadDidFinishWith: photo)
            }
            return
        }

        guard let url = photo.url else { return }

        let progress: Progress = { [weak self] _, receivedSize, totalSize in
            self?.executeInBackground { [weak self] in
                guard let self = self else { return }
                self.delegate?.networkIntegration?(
                    self, didUpdateLoadingProgress: CGFloat(receivedSize) / CGFloat(totalSize),
                    for: photo
                )
            }
        }

        let completion: Completion = { [weak self] response in
            guard let self = self else { return }

            self.retrieveImageTasks.removeObject(forKey: photo)

            switch response {
            case let .success(result):
                photo.image = result.image
                self.executeInBackground { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.networkIntegration(self, loadDidFinishWith: photo)
                }

            case let .failure(error):
                self.executeInBackground { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.networkIntegration(self, loadDidFailWith: error, for: photo)
                }
            }
        }

        let task = ImagePipeline.shared.loadImage(with: url, progress: progress, completion: completion)
        retrieveImageTasks.setObject(task, forKey: photo)
    }

    func cancelLoad(for photo: AXPhotoProtocol) {
        guard let downloadTask = retrieveImageTasks.object(forKey: photo) else { return }
        downloadTask.cancel()
    }

    func cancelAllLoads() {
        let enumerator = retrieveImageTasks.objectEnumerator()

        while let downloadTask = enumerator?.nextObject() as? ImageTask {
            downloadTask.cancel()
        }

        retrieveImageTasks.removeAllObjects()
    }
}
#endif
